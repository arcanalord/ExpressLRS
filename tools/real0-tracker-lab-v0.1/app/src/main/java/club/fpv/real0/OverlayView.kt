package club.fpv.real0

import android.content.Context
import android.graphics.*
import android.view.MotionEvent
import android.view.View
import kotlin.math.max
import kotlin.math.min

class OverlayView(ctx:Context):View(ctx){
    var frameW=0
    var frameH=0
    var result=TrackerResult(TrackState.IDLE,null,null,0f,0f,"")
    var onQuickLock:((PointF)->Unit)?=null
    var onPreciseLock:((RectF)->Unit)?=null

    private var quickMode=false
    private var armed=false
    private var down:PointF?=null
    private var drag:PointF?=null
    private val p=Paint(Paint.ANTI_ALIAS_FLAG).apply{style=Paint.Style.STROKE;strokeWidth=5f}
    private val text=Paint(Paint.ANTI_ALIAS_FLAG).apply{textSize=34f;typeface=Typeface.DEFAULT_BOLD}

    fun armQuick(){quickMode=true;armed=true;down=null;drag=null;invalidate()}
    fun armPrecise(){quickMode=false;armed=true;down=null;drag=null;invalidate()}
    fun disarm(){armed=false;down=null;drag=null;invalidate()}

    override fun onDraw(c:Canvas){
        super.onDraw(c)
        if(frameW<=0||frameH<=0)return

        result.predictedBox?.let{
            p.color=Color.rgb(49,211,242)
            p.pathEffect=DashPathEffect(floatArrayOf(14f,10f),0f)
            c.drawRect(map(it),p)
            p.pathEffect=null
        }

        result.measuredBox?.let{
            p.color=when(result.state){
                TrackState.TRACKING,TrackState.REACQUIRED->Color.rgb(70,217,154)
                TrackState.STABILIZING,TrackState.UNCERTAIN->Color.rgb(246,185,77)
                else->Color.WHITE
            }
            c.drawRect(map(it),p)
        }

        text.color=when(result.state){
            TrackState.LOST->Color.rgb(255,102,125)
            TrackState.STABILIZING,TrackState.UNCERTAIN,TrackState.SEARCHING->Color.rgb(246,185,77)
            else->Color.WHITE
        }
        c.drawText("${result.state} ${(result.quality*100).toInt()}%",24f,54f,text)

        val a=down
        val b=drag
        if(a!=null&&b!=null&&!quickMode){
            p.color=Color.CYAN
            p.pathEffect=DashPathEffect(floatArrayOf(12f,8f),0f)
            c.drawRect(RectF(min(a.x,b.x),min(a.y,b.y),max(a.x,b.x),max(a.y,b.y)),p)
            p.pathEffect=null
        }
    }

    override fun onTouchEvent(e:MotionEvent):Boolean{
        if(frameW<=0||frameH<=0||!armed)return false
        when(e.action){
            MotionEvent.ACTION_DOWN->{
                down=PointF(e.x,e.y)
                drag=PointF(e.x,e.y)
                invalidate()
            }
            MotionEvent.ACTION_MOVE->{
                drag=PointF(e.x,e.y)
                invalidate()
            }
            MotionEvent.ACTION_UP->{
                val a=down
                val b=PointF(e.x,e.y)
                if(a!=null){
                    if(quickMode){
                        onQuickLock?.invoke(unmapPoint(b))
                    }else if(kotlin.math.abs(a.x-b.x)>30&&kotlin.math.abs(a.y-b.y)>30){
                        onPreciseLock?.invoke(clamp(unmap(RectF(min(a.x,b.x),min(a.y,b.y),max(a.x,b.x),max(a.y,b.y)))))
                    }
                }
                disarm()
            }
            MotionEvent.ACTION_CANCEL->disarm()
        }
        return true
    }

    private fun scale():Float=min(width.toFloat()/frameW,height.toFloat()/frameH)
    private fun ox()=(width-frameW*scale())/2f
    private fun oy()=(height-frameH*scale())/2f
    private fun map(r:RectF)=RectF(ox()+r.left*scale(),oy()+r.top*scale(),ox()+r.right*scale(),oy()+r.bottom*scale())
    private fun unmap(r:RectF)=RectF((r.left-ox())/scale(),(r.top-oy())/scale(),(r.right-ox())/scale(),(r.bottom-oy())/scale())
    private fun unmapPoint(p:PointF)=PointF(
        ((p.x-ox())/scale()).coerceIn(1f,frameW-2f),
        ((p.y-oy())/scale()).coerceIn(1f,frameH-2f)
    )
    private fun clamp(r:RectF)=RectF(
        r.left.coerceIn(1f,frameW-2f),r.top.coerceIn(1f,frameH-2f),
        r.right.coerceIn(2f,frameW-1f),r.bottom.coerceIn(2f,frameH-1f)
    )
}
