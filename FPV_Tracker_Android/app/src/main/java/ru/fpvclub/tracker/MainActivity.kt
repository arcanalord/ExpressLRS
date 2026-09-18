package ru.fpvclub.tracker

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.RectF
import android.os.Bundle
import android.util.Size
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.*
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import org.opencv.android.OpenCVLoader
import ru.fpvclub.tracker.camera.CameraFrameConverter
import ru.fpvclub.tracker.camera.CoordinateMapper
import ru.fpvclub.tracker.databinding.ActivityMainBinding
import ru.fpvclub.tracker.tracking.*
import java.util.Locale
import java.util.concurrent.Executors

class MainActivity:ComponentActivity(){
    private lateinit var b:ActivityMainBinding;private val executor=Executors.newSingleThreadExecutor();private val tracker=AdaptiveTracker()
    @Volatile private var pendingBox:Box?=null;private var lastDebugUiMs=0L
    private val permission=registerForActivityResult(ActivityResultContracts.RequestPermission()){if(it)startCamera() else showFatal("Нет разрешения на камеру")}
    override fun onCreate(s:Bundle?){super.onCreate(s);b=ActivityMainBinding.inflate(layoutInflater);setContentView(b.root)
        if(!OpenCVLoader.initLocal()){showFatal("OpenCV не загрузился");return}
        b.preview.scaleType=PreviewView.ScaleType.FIT_CENTER;b.preview.implementationMode=PreviewView.ImplementationMode.COMPATIBLE
        b.overlay.onBoxSelected={pendingBox=it;b.stateText.text="CAPTURE";b.debugText.text="Фиксирую цель…"};b.newTarget.setOnClickListener{resetUi()};b.reset.setOnClickListener{resetUi()}
        if(ContextCompat.checkSelfPermission(this,Manifest.permission.CAMERA)==PackageManager.PERMISSION_GRANTED)b.preview.post{startCamera()} else permission.launch(Manifest.permission.CAMERA)}
    private fun resetUi(){tracker.reset();pendingBox=null;b.overlay.trackBox=null;b.overlay.state=TrackState.IDLE;b.overlay.invalidate();b.stateText.text="IDLE";b.debugText.text="Обведите цель рамкой"}
    private fun startCamera(){val future=ProcessCameraProvider.getInstance(this);future.addListener({val provider=future.get();val preview=Preview.Builder().setTargetRotation(b.preview.display.rotation).build().also{it.surfaceProvider=b.preview.surfaceProvider}
        val selector=ResolutionSelector.Builder().setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY).setResolutionStrategy(ResolutionStrategy(Size(640,480),ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER)).build()
        val analysis=ImageAnalysis.Builder().setTargetRotation(b.preview.display.rotation).setResolutionSelector(selector).setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build();analysis.setAnalyzer(executor,::analyze);provider.unbindAll();provider.bindToLifecycle(this,CameraSelector.DEFAULT_BACK_CAMERA,preview,analysis)},ContextCompat.getMainExecutor(this))}
    private fun analyze(img:ImageProxy){val gray=try{CameraFrameConverter.grayUpright(img)}catch(t:Throwable){img.close();runOnUiThread{showFatal("Кадр камеры: \${t.javaClass.simpleName}")};return};try{
        val mapper=CoordinateMapper(gray.cols(),gray.rows(),b.overlay.width.coerceAtLeast(1),b.overlay.height.coerceAtLeast(1));pendingBox?.let{pendingBox=null;tracker.capture(gray,mapper.viewToImage(it))};val r=tracker.update(gray);val now=System.currentTimeMillis();runOnUiThread{b.stateText.text=r.state.name;b.overlay.state=r.state;r.box?.let{val q=mapper.imageToView(it);b.overlay.trackBox=RectF(q.x,q.y,q.x+q.w,q.y+q.h)}?:run{b.overlay.trackBox=null};b.overlay.invalidate();if(now-lastDebugUiMs>=120){lastDebugUiMs=now;b.debugText.text="\${r.mode} · pts \${r.points} · inl \${(r.inlierRatio*100).toInt()}% · q \${String.format(Locale.US,"%.2f",r.quality)} · cam \${(r.cameraInlierRatio*100).toInt()}% · Δ \${String.format(Locale.US,"%.0f/%.0f",r.cameraDx,r.cameraDy)}"}}}finally{gray.release();img.close()}}
    private fun showFatal(m:String){if(::b.isInitialized){b.stateText.text="ERROR";b.debugText.text=m}}
    override fun onDestroy(){super.onDestroy();executor.shutdown()}
}
