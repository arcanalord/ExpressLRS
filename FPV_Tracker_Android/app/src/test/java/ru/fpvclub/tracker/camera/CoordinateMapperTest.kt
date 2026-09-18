package ru.fpvclub.tracker.camera

import org.junit.Assert.assertEquals
import org.junit.Test
import ru.fpvclub.tracker.tracking.Box

class CoordinateMapperTest {
    @Test fun roundTripPreservesBox() {
        val mapper = CoordinateMapper(640, 480, 1080, 1920)
        val source = Box(150f, 120f, 220f, 140f)
        val result = mapper.viewToImage(mapper.imageToView(source))
        assertEquals(source.x, result.x, 0.01f)
        assertEquals(source.y, result.y, 0.01f)
        assertEquals(source.w, result.w, 0.01f)
        assertEquals(source.h, result.h, 0.01f)
    }
}
