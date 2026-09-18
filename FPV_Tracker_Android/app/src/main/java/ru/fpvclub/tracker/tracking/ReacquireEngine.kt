package ru.fpvclub.tracker.tracking

import org.opencv.calib3d.Calib3d
import org.opencv.core.*
import org.opencv.features2d.BFMatcher
import org.opencv.features2d.ORB
import org.opencv.imgproc.Imgproc
import kotlin.math.sqrt

/** Long-term visual memory for reacquisition after LK flow breaks. */
class ReacquireEngine {
    private data class Keyframe(val points: Array<KeyPoint>, val desc: Mat, val box: Box, val name: String)

    private val orb = ORB.create(1200, 1.2f, 8, 21, 0, 2, ORB.HARRIS_SCORE, 21, 12)
    private val matcher = BFMatcher.create(Core.NORM_HAMMING, false)
    private var anchor: Keyframe? = null
    private var recent: Keyframe? = null
    private var goodFrames = 0

    fun reset() { anchor?.desc?.release(); recent?.desc?.release(); anchor = null; recent = null; goodFrames = 0 }

    fun capture(gray: Mat, box: Box) {
        reset(); anchor = buildKeyframe(gray, box, "anchor")
    }

    fun observeGood(gray: Mat, box: Box, quality: Float) {
        if (quality < .78f) { goodFrames = 0; return }
        goodFrames++
        if (goodFrames < 24) return
        goodFrames = 0
        val k = buildKeyframe(gray, box, "recent") ?: return
        recent?.desc?.release(); recent = k
    }

    fun search(gray: Mat, hint: Box? = null): ReacquireResult {
        val local = hint?.let { searchRegion(gray, expand(it, 2.7f, gray.cols(), gray.rows()), "local") }
        if (local != null && local.quality >= .54f) return local
        return searchRegion(gray, null, "global") ?: ReacquireResult(null, 0f, 0, 0f, "none")
    }

    private fun searchRegion(gray: Mat, region: Box?, pass: String): ReacquireResult? {
        val mask = if (region != null) maskFor(gray, region) else Mat()
        val kp = MatOfKeyPoint(); val desc = Mat()
        orb.detectAndCompute(gray, mask, kp, desc)
        if (!mask.empty()) mask.release()
        if (desc.empty() || kp.rows() < 8) { kp.release(); desc.release(); return null }
        val framePts = kp.toArray(); kp.release()
        val candidates = listOfNotNull(anchor, recent)
        var best: ReacquireResult? = null
        for (key in candidates) {
            val r = matchKeyframe(key, framePts, desc, gray.cols(), gray.rows(), pass) ?: continue
            if (best == null || r.quality > best!!.quality) best = r
        }
        desc.release(); return best
    }

    private fun matchKeyframe(key: Keyframe, framePts: Array<KeyPoint>, frameDesc: Mat, width: Int, height: Int, pass: String): ReacquireResult? {
        if (key.desc.empty()) return null
        val knn = ArrayList<MatOfDMatch>()
        matcher.knnMatch(key.desc, frameDesc, knn, 2)
        val src = ArrayList<Point>(); val dst = ArrayList<Point>()
        for (pair in knn) {
            val m = pair.toArray(); pair.release()
            if (m.size >= 2 && m[0].distance < m[1].distance * .74f && m[0].distance < 72f) {
                val q = m[0].queryIdx; val t = m[0].trainIdx
                if (q in key.points.indices && t in framePts.indices) { src += key.points[q].pt; dst += framePts[t].pt }
            }
        }
        if (src.size < 8) return null
        val sm = MatOfPoint2f(*src.toTypedArray()); val dm = MatOfPoint2f(*dst.toTypedArray()); val inliers = Mat()
        val affine = Calib3d.estimateAffinePartial2D(sm, dm, inliers, Calib3d.RANSAC, 3.5)
        if (affine.empty()) { sm.release(); dm.release(); inliers.release(); affine.release(); return null }
        val m00=affine.get(0,0)[0]; val m01=affine.get(0,1)[0]; val tx=affine.get(0,2)[0]
        val m10=affine.get(1,0)[0]; val m11=affine.get(1,1)[0]; val ty=affine.get(1,2)[0]
        fun tr(x:Double,y:Double)=Point(m00*x+m01*y+tx,m10*x+m11*y+ty)
        val p=arrayOf(tr(key.box.x.toDouble(),key.box.y.toDouble()),tr((key.box.x+key.box.w).toDouble(),key.box.y.toDouble()),tr((key.box.x+key.box.w).toDouble(),(key.box.y+key.box.h).toDouble()),tr(key.box.x.toDouble(),(key.box.y+key.box.h).toDouble()))
        val minX=p.minOf{it.x}; val maxX=p.maxOf{it.x}; val minY=p.minOf{it.y}; val maxY=p.maxOf{it.y}
        val box=clamp(Box(minX.toFloat(),minY.toFloat(),(maxX-minX).toFloat(),(maxY-minY).toFloat()),width,height)
        val mask=inliers.toArray(); val inlierCount=mask.count{it.toInt()!=0}; val ratio=inlierCount/maxOf(1f,mask.size.toFloat())
        val scale=sqrt(m00*m00+m10*m10).toFloat()
        val matchFactor=(src.size/26f).coerceIn(0f,1f)
        val quality=(ratio*.72f+matchFactor*.28f).coerceIn(0f,1f)
        sm.release(); dm.release(); inliers.release(); affine.release()
        if (ratio < .42f || src.size < 9 || scale !in .45f..2.2f || box.w < 12f || box.h < 12f) return null
        return ReacquireResult(box,quality,src.size,ratio,"\${pass}:\${key.name}")
    }

    private fun buildKeyframe(gray: Mat, box: Box, name: String): Keyframe? {
        val mask = maskFor(gray, box); val kp = MatOfKeyPoint(); val desc = Mat()
        orb.detectAndCompute(gray, mask, kp, desc); mask.release()
        if (desc.empty() || kp.rows() < 10) { kp.release(); desc.release(); return null }
        val points=kp.toArray(); kp.release(); return Keyframe(points,desc,box,name)
    }

    private fun maskFor(gray: Mat, b: Box): Mat {
        val mask=Mat.zeros(gray.size(),CvType.CV_8UC1); Imgproc.rectangle(mask,Point(b.x.toDouble(),b.y.toDouble()),Point((b.x+b.w).toDouble(),(b.y+b.h).toDouble()),Scalar(255.0),-1); return mask
    }
    private fun expand(b:Box,f:Float,w:Int,h:Int):Box{val nw=(b.w*f).coerceAtMost(w.toFloat());val nh=(b.h*f).coerceAtMost(h.toFloat());return clamp(Box(b.cx-nw/2,b.cy-nh/2,nw,nh),w,h)}
    private fun clamp(b:Box,w:Int,h:Int):Box{val bw=b.w.coerceIn(12f,w.toFloat());val bh=b.h.coerceIn(12f,h.toFloat());return Box(b.x.coerceIn(0f,w-bw),b.y.coerceIn(0f,h-bh),bw,bh)}
}
