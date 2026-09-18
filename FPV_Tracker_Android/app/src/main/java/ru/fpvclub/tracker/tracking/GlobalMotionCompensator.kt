package ru.fpvclub.tracker.tracking

import org.opencv.calib3d.Calib3d
import org.opencv.core.*
import org.opencv.imgproc.Imgproc
import org.opencv.video.Video
import kotlin.math.hypot

/** Estimates camera/background motion from features outside the target box. */
class GlobalMotionCompensator {
    fun estimate(prevGray: Mat, gray: Mat, target: Box?): MotionEstimate {
        val mask = Mat(prevGray.rows(), prevGray.cols(), CvType.CV_8UC1, Scalar(255.0))
        target?.let { excludeTarget(mask, it) }
        val corners = MatOfPoint()
        Imgproc.goodFeaturesToTrack(prevGray, corners, 100, .012, 12.0, mask, 5, false, .04)
        mask.release()
        val oldArray = corners.toArray()
        corners.release()
        if (oldArray.size < 10) return MotionEstimate.identity("CAMERA_TOO_FEW_POINTS")

        val oldPts = MatOfPoint2f(*oldArray)
        val forward = MatOfPoint2f(); val stF = MatOfByte(); val errF = MatOfFloat()
        Video.calcOpticalFlowPyrLK(prevGray, gray, oldPts, forward, stF, errF, Size(31.0,31.0), 4,
            TermCriteria(TermCriteria.COUNT or TermCriteria.EPS, 24, .01), 0, 1e-4)
        val backward = MatOfPoint2f(); val stB = MatOfByte(); val errB = MatOfFloat()
        Video.calcOpticalFlowPyrLK(gray, prevGray, forward, backward, stB, errB, Size(31.0,31.0), 4,
            TermCriteria(TermCriteria.COUNT or TermCriteria.EPS, 24, .01), 0, 1e-4)

        val fwd = forward.toArray(); val back = backward.toArray(); val sf = stF.toArray(); val sb = stB.toArray()
        val src = ArrayList<Point>(); val dst = ArrayList<Point>(); var fbSum = 0.0
        for (i in oldArray.indices) {
            if (i >= sf.size || i >= sb.size || i >= fwd.size || i >= back.size) continue
            if (sf[i].toInt() == 0 || sb[i].toInt() == 0) continue
            val fb = hypot(oldArray[i].x - back[i].x, oldArray[i].y - back[i].y)
            if (fb <= 2.8) { src += oldArray[i]; dst += fwd[i]; fbSum += fb }
        }
        oldPts.release(); forward.release(); backward.release(); stF.release(); stB.release(); errF.release(); errB.release()
        if (src.size < 10) return MotionEstimate.identity("CAMERA_FB_REJECT")

        val sm = MatOfPoint2f(*src.toTypedArray()); val dm = MatOfPoint2f(*dst.toTypedArray()); val inliers = Mat()
        val affine = Calib3d.estimateAffinePartial2D(sm, dm, inliers, Calib3d.RANSAC, 3.0)
        sm.release(); dm.release()
        if (affine.empty()) { inliers.release(); affine.release(); return MotionEstimate.identity("CAMERA_NO_AFFINE") }
        val inlierMask = inliers.toArray(); val inlierCount = inlierMask.count { it.toInt() != 0 }
        val ratio = inlierCount / maxOf(1f, inlierMask.size.toFloat()); inliers.release()
        val a00=affine.get(0,0)[0]; val a01=affine.get(0,1)[0]; val tx=affine.get(0,2)[0]
        val a10=affine.get(1,0)[0]; val a11=affine.get(1,1)[0]; val ty=affine.get(1,2)[0]
        val reliable = inlierCount >= 8 && ratio >= .55f
        return MotionEstimate(affine,reliable,src.size,inlierCount,ratio,(fbSum/src.size).toFloat(),tx.toFloat(),ty.toFloat(),a00,a01,a10,a11,
            if(reliable) "CAMERA_OK" else "CAMERA_WEAK")
    }

    private fun excludeTarget(mask: Mat, b: Box) {
        val px=b.w*.35f; val py=b.h*.35f
        Imgproc.rectangle(mask,
            Point((b.x-px).coerceAtLeast(0f).toDouble(),(b.y-py).coerceAtLeast(0f).toDouble()),
            Point((b.x+b.w+px).coerceAtMost(mask.cols()-1f).toDouble(),(b.y+b.h+py).coerceAtMost(mask.rows()-1f).toDouble()),
            Scalar(0.0),-1)
    }
}

data class MotionEstimate(
    val affine: Mat, val reliable:Boolean, val points:Int, val inliers:Int, val inlierRatio:Float,
    val fbError:Float, val dx:Float, val dy:Float,
    val a00:Double, val a01:Double, val a10:Double, val a11:Double, val mode:String
) {
    fun transform(p: Point)=Point(a00*p.x+a01*p.y+dx,a10*p.x+a11*p.y+dy)
    fun transform(b:Box,w:Int,h:Int):Box {
        val p=arrayOf(transform(Point(b.x.toDouble(),b.y.toDouble())),transform(Point((b.x+b.w).toDouble(),b.y.toDouble())),
            transform(Point((b.x+b.w).toDouble(),(b.y+b.h).toDouble())),transform(Point(b.x.toDouble(),(b.y+b.h).toDouble())))
        val minX=p.minOf{it.x}.toFloat(); val maxX=p.maxOf{it.x}.toFloat(); val minY=p.minOf{it.y}.toFloat(); val maxY=p.maxOf{it.y}.toFloat()
        val bw=(maxX-minX).coerceIn(12f,w.toFloat()); val bh=(maxY-minY).coerceIn(12f,h.toFloat())
        return Box(minX.coerceIn(0f,w-bw),minY.coerceIn(0f,h-bh),bw,bh)
    }
    fun release()=affine.release()
    companion object {
        fun identity(mode:String): MotionEstimate {
            val affine = Mat(2, 3, CvType.CV_64F, Scalar(0.0))
            affine.put(0, 0, 1.0)
            affine.put(1, 1, 1.0)
            return MotionEstimate(affine,false,0,0,0f,99f,0f,0f,1.0,0.0,0.0,1.0,mode)
        }
    }
}
