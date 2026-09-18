package ru.fpvclub.tracker.tracking

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class MotionModelTest {
    @Test fun predictsConstantMotionAcrossFrames() {
        val model = MotionModel()
        model.reset(Box(10f, 20f, 40f, 30f))
        model.update(Box(14f, 22f, 40f, 30f))
        model.update(Box(18f, 24f, 40f, 30f))
        model.update(Box(22f, 26f, 40f, 30f))
        val predicted = assertNotNull(model.predict(1f)) as Box
        assertEquals(26f, predicted.x, 0.8f)
        assertEquals(28f, predicted.y, 0.8f)
    }

    @Test fun singleOutlierDoesNotDominatePrediction() {
        val model = MotionModel()
        model.reset(Box(0f, 0f, 50f, 40f))
        model.update(Box(3f, 2f, 50f, 40f))
        model.update(Box(6f, 4f, 50f, 40f))
        model.update(Box(40f, 30f, 50f, 40f))
        model.update(Box(12f, 8f, 50f, 40f))
        val predicted = assertNotNull(model.predict(1f)) as Box
        assertEquals(15f, predicted.x, 3.5f)
        assertEquals(10f, predicted.y, 3.5f)
    }
}
