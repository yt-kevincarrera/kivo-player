package dev.selector.kivo_player

import org.junit.Assert.*
import org.junit.Test

class PreviewFrameSizeTest {
    @Test fun bitmapBudgetPreservesShapeAndBoundsBothOrientations() {
        assertEquals(240 to 135, PreviewFrameSize.fit(3840, 2160))
        assertEquals(135 to 240, PreviewFrameSize.fit(2160, 3840))
        assertEquals(240 to 135, PreviewFrameSize.fit(7680, 4320))
        assertEquals(1 to 240, PreviewFrameSize.fit(1, Int.MAX_VALUE))
        assertEquals(160 to 90, PreviewFrameSize.fit(160, 90))
    }
}
