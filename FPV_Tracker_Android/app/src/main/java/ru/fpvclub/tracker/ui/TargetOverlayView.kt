package ru.fpvclub.tracker.ui

import android.content.Context
import android.graphics.*
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import ru.fpvclub.tracker.tracking.Box
import ru.fpvclub.tracker.tracking.TrackState

class TargetOverlayView @JvmOverloads constructor(c: Context, a: AttributeSet?=null): View(c,a) {
    var onBoxSelected: ((Box)->Unit)? = null
    private val paint=Paint(Paint.ANTI_ALIAS_FLAG).apply{style=Paint.Style.STROKE;strokeWidth=4f;color=Color.rgb(70,217,154)}
    private var start: PointF?=null; private var current: RectF?=null
    var trackBox: RectF?=null; var state: TrackState=TrackState.IDLE
    override fun onTouchEvent(e: MotionEvent): Boolean { when(e.actionMasked){
        MotionEvent.ACTION_DOWN->{start=PointF(e.x,e.y);current=RectF(e.x,e.y,e.x,e.y);invalidate();return true}
        MotionEvent.ACTION_MOVE->{val s=start?:return false;current=RectF(minOf(s.x,e.x),minOf(s.y,e.y),maxOf(s.x,e.x),maxOf(s.y,e.y));invalidate();return true}
        MotionEvent.ACTION_UP->{val r=current;start=null;current=null;if(r!=null&&r.width()>32&&r.height()>32)onBoxSelected?.invoke(Box(r.left,r.top,r.width(),r.height()));invalidate();return true}
    };return true }
    override fun onDraw(c: Canvas){super.onDraw(c);paint.color=when(state){TrackState.TRACK,TrackState.REACQUIRED->Color.rgb(70,217,154);TrackState.SEARCH->Color.rgb(246,185,77);else->Color.rgb(49,211,242)};current?.let{c.drawRect(it,paint)};trackBox?.let{c.drawRect(it,paint)}}
}
