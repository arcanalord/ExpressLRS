package ru.fpvclub.tracker.camera

import ru.fpvclub.tracker.tracking.Box

/** FIT_CENTER mapping between upright analysis image and overlay view. */
class CoordinateMapper(private val imageW:Int, private val imageH:Int, private val viewW:Int, private val viewH:Int) {
    private val scale = minOf(viewW / imageW.toFloat(), viewH / imageH.toFloat())
    private val ox = (viewW - imageW * scale) * .5f
    private val oy = (viewH - imageH * scale) * .5f
    fun viewToImage(b:Box):Box = Box((b.x-ox)/scale,(b.y-oy)/scale,b.w/scale,b.h/scale).clamped(imageW,imageH)
    fun imageToView(b:Box):Box = Box(ox+b.x*scale,oy+b.y*scale,b.w*scale,b.h*scale)
    private fun Box.clamped(w:Int,h:Int):Box{val bw=this.w.coerceIn(12f,w.toFloat());val bh=this.h.coerceIn(12f,h.toFloat());return Box(x.coerceIn(0f,w-bw),y.coerceIn(0f,h-bh),bw,bh)}
}
