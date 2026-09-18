package ru.fpvclub.tracker.tracking

import org.opencv.calib3d.Calib3d
import org.opencv.core.*
import org.opencv.imgproc.Imgproc
import org.opencv.video.Video
import kotlin.math.hypot
import kotlin.math.sqrt

/** Short-term target tracker with camera-motion seeded LK optical flow. */
class OpticalFlowTracker {
    private var prevGray:Mat?=null
    private var prevPts=MatOfPoint2f()
    private var box:Box?=null
    private var frameIndex=0
    private val cameraMotion=GlobalMotionCompensator()
    var state:TrackState=TrackState.IDLE; private set

    fun reset(){prevGray?.release();prevGray=null;prevPts.release();prevPts=MatOfPoint2f();box=null;frameIndex=0;state=TrackState.IDLE}
    fun capture(gray:Mat,selected:Box):TrackResult{
        reset();box=clamp(selected,gray.cols(),gray.rows());prevGray=gray.clone();reseed(gray,box!!)
        state=if(prevPts.rows()>=MIN_POINTS)TrackState.TRACK else TrackState.SEARCH
        return TrackResult(state,box,if(state==TrackState.TRACK)1f else 0f,1f,prevPts.rows().toInt(),"CAPTURE")
    }

    fun update(gray:Mat):TrackResult{
        val pg=prevGray?:return idle();val oldBox=box?:return idle()
        val camera=cameraMotion.estimate(pg,gray,oldBox)
        val predicted=if(camera.reliable)camera.transform(oldBox,gray.cols(),gray.rows()) else oldBox
        if(prevPts.rows()<MIN_POINTS)return enterSearch(gray,predicted,"FLOW_LOW_POINTS",camera)

        val old=prevPts.toArray()
        val initial=if(camera.reliable)old.map(camera::transform).toTypedArray() else emptyArray()
        val forward=if(initial.isNotEmpty())MatOfPoint2f(*initial) else MatOfPoint2f();val stF=MatOfByte();val errF=MatOfFloat()
        Video.calcOpticalFlowPyrLK(pg,gray,prevPts,forward,stF,errF,Size(31.0,31.0),4,TermCriteria(TermCriteria.COUNT or TermCriteria.EPS,30,.01),if(initial.isNotEmpty())OPTFLOW_USE_INITIAL_FLOW else 0,1e-4)
        val backward=MatOfPoint2f();val stB=MatOfByte();val errB=MatOfFloat()
        Video.calcOpticalFlowPyrLK(gray,pg,forward,backward,stB,errB,Size(31.0,31.0),4,TermCriteria(TermCriteria.COUNT or TermCriteria.EPS,30,.01),0,1e-4)

        val fwd=forward.toArray();val back=backward.toArray();val sf=stF.toArray();val sb=stB.toArray()
        val src=ArrayList<Point>();val dst=ArrayList<Point>();var fbSum=0.0
        for(i in old.indices){if(i>=sf.size||i>=sb.size||i>=fwd.size||i>=back.size)continue;if(sf[i].toInt()==0||sb[i].toInt()==0)continue
            val fb=hypot(old[i].x-back[i].x,old[i].y-back[i].y);if(fb<=FB_MAX){src+=old[i];dst+=fwd[i];fbSum+=fb}}
        forward.release();backward.release();stF.release();stB.release();errF.release();errB.release()
        val survival=src.size/maxOf(1f,old.size.toFloat());val fbMean=if(src.isEmpty())99f else (fbSum/src.size).toFloat()
        if(src.size<MIN_POINTS)return enterSearch(gray,predicted,"FLOW_FB_REJECT",camera,survival*.25f,0f,src.size,1f,fbMean)

        val sm=MatOfPoint2f(*src.toTypedArray());val dm=MatOfPoint2f(*dst.toTypedArray());val inliers=Mat()
        val affine=Calib3d.estimateAffinePartial2D(sm,dm,inliers,Calib3d.RANSAC,2.5)
        if(affine.empty()){sm.release();dm.release();inliers.release();affine.release();return enterSearch(gray,predicted,"FLOW_NO_AFFINE",camera,targetPoints=src.size,fbError=fbMean)}
        val m00=affine.get(0,0)[0];val m01=affine.get(0,1)[0];val tx=affine.get(0,2)[0];val m10=affine.get(1,0)[0];val m11=affine.get(1,1)[0];val ty=affine.get(1,2)[0]
        fun tr(x:Double,y:Double)=Point(m00*x+m01*y+tx,m10*x+m11*y+ty)
        val p=arrayOf(tr(oldBox.x.toDouble(),oldBox.y.toDouble()),tr((oldBox.x+oldBox.w).toDouble(),oldBox.y.toDouble()),tr((oldBox.x+oldBox.w).toDouble(),(oldBox.y+oldBox.h).toDouble()),tr(oldBox.x.toDouble(),(oldBox.y+oldBox.h).toDouble()))
        val next=clamp(Box(p.minOf{it.x}.toFloat(),p.minOf{it.y}.toFloat(),(p.maxOf{it.x}-p.minOf{it.x}).toFloat(),(p.maxOf{it.y}-p.minOf{it.y}).toFloat()),gray.cols(),gray.rows())
        val mask=inliers.toArray();val inlierCount=mask.count{it.toInt()!=0};val inlierRatio=inlierCount/maxOf(1f,mask.size.toFloat());val scale=sqrt(m00*m00+m10*m10).toFloat()
        val pointFactor=(src.size/36f).coerceIn(0f,1f);val fbFactor=(1f-fbMean/FB_MAX.toFloat()).coerceIn(0f,1f);val quality=(inlierRatio*.60f+pointFactor*.25f+fbFactor*.15f).coerceIn(0f,1f)
        val sane=scale in .72f..1.38f&&next.w>=12f&&next.h>=12f
        sm.release();dm.release();inliers.release();affine.release()
        if(quality<TRACK_MIN||!sane)return enterSearch(gray,predicted,"FLOW_QUALITY_DROP",camera,quality,inlierRatio,src.size,scale,fbMean)

        state=TrackState.TRACK;box=smooth(oldBox,next);prevGray?.release();prevGray=gray.clone();frameIndex++
        if(frameIndex%RESEED_EVERY==0||src.size<RESEED_BELOW)reseed(gray,box!!) else {prevPts.release();prevPts=MatOfPoint2f(*dst.toTypedArray())}
        val result=TrackResult(state,box,quality,inlierRatio,src.size,if(camera.reliable)"FLOW_CAMERA_SEEDED" else "FLOW",scale,fbMean,camera.inlierRatio,camera.inliers,camera.dx,camera.dy)
        camera.release();return result
    }

    private fun enterSearch(gray:Mat,predicted:Box,mode:String,camera:MotionEstimate,quality:Float=0f,inlierRatio:Float=0f,targetPoints:Int=0,scale:Float=1f,fbError:Float=0f):TrackResult{
        state=TrackState.SEARCH;box=predicted;prevGray?.release();prevGray=gray.clone();prevPts.release();prevPts=MatOfPoint2f()
        val r=TrackResult(state,box,quality,inlierRatio,targetPoints,if(camera.reliable)"\${mode}_CAMERA_PROPAGATED" else mode,scale,fbError,camera.inlierRatio,camera.inliers,camera.dx,camera.dy);camera.release();return r
    }
    private fun reseed(gray:Mat,b:Box){val mask=Mat.zeros(gray.size(),CvType.CV_8UC1);val ix=(b.w*.05f).toInt();val iy=(b.h*.05f).toInt();Imgproc.rectangle(mask,Point((b.x+ix).toDouble(),(b.y+iy).toDouble()),Point((b.x+b.w-ix).toDouble(),(b.y+b.h-iy).toDouble()),Scalar(255.0),-1);val c=MatOfPoint();Imgproc.goodFeaturesToTrack(gray,c,140,.008,4.0,mask,5,false,.04);prevPts.release();prevPts=MatOfPoint2f(*c.toArray());c.release();mask.release()}
    private fun smooth(a:Box,b:Box)=Box(a.x+(b.x-a.x)*.78f,a.y+(b.y-a.y)*.78f,a.w+(b.w-a.w)*.48f,a.h+(b.h-a.h)*.48f)
    private fun clamp(b:Box,w:Int,h:Int):Box{val bw=b.w.coerceIn(12f,w.toFloat());val bh=b.h.coerceIn(12f,h.toFloat());return Box(b.x.coerceIn(0f,w-bw),b.y.coerceIn(0f,h-bh),bw,bh)}
    private fun idle()=TrackResult(TrackState.IDLE,null,0f,0f,0,"IDLE")
    companion object{private const val MIN_POINTS=10;private const val RESEED_BELOW=34;private const val RESEED_EVERY=10;private const val FB_MAX=2.2;private const val TRACK_MIN=.50f;private const val OPTFLOW_USE_INITIAL_FLOW=4}
}
