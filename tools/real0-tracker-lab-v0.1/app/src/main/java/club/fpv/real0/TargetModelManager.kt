package club.fpv.real0

import android.graphics.Bitmap
import android.graphics.RectF
import kotlin.math.sqrt

class TargetModelManager {
    private var anchor = FloatArray(0)
    private var stable = FloatArray(0)
    private var adaptive = FloatArray(0)
    private var sampleW = 0
    private var sampleH = 0
    var updates = 0; private set
    var restores = 0; private set
    var policy = "RESET"; private set
    val ready get() = adaptive.isNotEmpty()

    fun reset(){ anchor=FloatArray(0);stable=FloatArray(0);adaptive=FloatArray(0);sampleW=0;sampleH=0;updates=0;restores=0;policy="RESET" }
    fun init(frame:Bitmap,box:RectF,width:Int,height:Int){sampleW=width;sampleH=height;val s=sample(frame,box);anchor=s.copyOf();stable=s.copyOf();adaptive=s.copyOf();policy="HOLD"}
    fun score(frame:Bitmap,box:RectF):Float{if(!ready)return 0f;val s=sample(frame,box);val raw=.25f*dot(anchor,s)+.25f*dot(stable,s)+.5f*dot(adaptive,s);return ((raw+1f)*.5f).coerceIn(0f,1f)}
    fun commit(frame:Bitmap,box:RectF,quality:Float){if(!ready||quality<.70f){policy="HOLD";return};val s=sample(frame,box);for(i in adaptive.indices)adaptive[i]=.97f*adaptive[i]+.03f*s[i];norm(adaptive);updates++;policy="UPDATE";if(updates%30==0&&quality>=.76f)stable=adaptive.copyOf()}
    fun restore(){if(stable.isNotEmpty()){adaptive=stable.copyOf();restores++;policy="RESTORE_STABLE"}}
    private fun sample(bm:Bitmap,r:RectF):FloatArray{val out=FloatArray(sampleW*sampleH);for(y in 0 until sampleH){val py=(r.top+(y+.5f)*r.height()/sampleH).toInt().coerceIn(0,bm.height-1);for(x in 0 until sampleW){val px=(r.left+(x+.5f)*r.width()/sampleW).toInt().coerceIn(0,bm.width-1);val c=bm.getPixel(px,py);out[y*sampleW+x]=(0.299f*((c shr 16) and 255)+0.587f*((c shr 8) and 255)+0.114f*(c and 255))/255f}};norm(out);return out}
    private fun dot(a:FloatArray,b:FloatArray):Float{var s=0f;for(i in a.indices)s+=a[i]*b[i];return s}
    private fun norm(a:FloatArray){if(a.isEmpty())return;var m=0f;for(v in a)m+=v;m/=a.size;var ss=0f;for(i in a.indices){a[i]-=m;ss+=a[i]*a[i]};val d=sqrt(ss.coerceAtLeast(1e-9f));for(i in a.indices)a[i]/=d}
}
