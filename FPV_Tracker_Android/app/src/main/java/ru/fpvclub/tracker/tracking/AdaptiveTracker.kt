package ru.fpvclub.tracker.tracking

import org.opencv.core.Mat

class AdaptiveTracker {
    private val flow=OpticalFlowTracker(); private val reacquire=ReacquireEngine(); private val motion=MotionModel()
    private var lastConfirmedBox:Box?=null; private var searchFrames=0
    fun reset(){flow.reset();reacquire.reset();motion.reset();lastConfirmedBox=null;searchFrames=0}
    fun capture(gray:Mat,box:Box):TrackResult{reset();reacquire.capture(gray,box);motion.reset(box);lastConfirmedBox=box;return flow.capture(gray,box)}
    fun update(gray:Mat):TrackResult{
        val fr=flow.update(gray)
        if(fr.state==TrackState.TRACK&&fr.box!=null){motion.update(fr.box);lastConfirmedBox=fr.box;searchFrames=0;reacquire.observeGood(gray,fr.box,fr.quality);return fr}
        if(fr.state==TrackState.IDLE)return fr
        searchFrames++
        val temporal=motion.predict(searchFrames.coerceAtMost(5).toFloat())
        val cameraHint=fr.box?.takeIf{fr.mode.contains("CAMERA_PROPAGATED")}
        val hint=cameraHint?:temporal?:lastConfirmedBox
        val found=reacquire.search(gray,hint)
        if(found.box!=null&&found.quality>=.56f){
            val seeded=flow.capture(gray,found.box)
            if(seeded.state==TrackState.TRACK){motion.reset(found.box);lastConfirmedBox=found.box;searchFrames=0
                return TrackResult(TrackState.REACQUIRED,found.box,found.quality,found.inlierRatio,found.matches,"REACQUIRE_\${found.source}",seeded.scale,seeded.fbError,fr.cameraInlierRatio,fr.cameraPoints,fr.cameraDx,fr.cameraDy)}
        }
        return TrackResult(TrackState.SEARCH,hint,found.quality,found.inlierRatio,found.matches,"SEARCH_\${found.source}",cameraInlierRatio=fr.cameraInlierRatio,cameraPoints=fr.cameraPoints,cameraDx=fr.cameraDx,cameraDy=fr.cameraDy)
    }
}
