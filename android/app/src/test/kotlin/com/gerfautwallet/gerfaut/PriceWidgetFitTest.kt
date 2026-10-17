package com.gerfautwallet.gerfaut

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// Which lines of the price widget show, at the sizes the Pixel launcher
// grants on a Pixel 7 (Android 16, read from appwidgets.xml on the
// emulator, 17 October 2026): the 2x1 the widget is placed at is 172 x
// 104 dp upright and 306 x 62 dp on its side, and the widget sizes
// itself against the smallest height, 62. Line heights as the emulator
// draws them at 420 dpi, for text at its usual size and at twice it.
class PriceWidgetFitTest {
    private class Text(val small: Float, val figure: Float, val figureMin: Float)

    private val usual = Text(small = 16.4f, figure = 29.7f, figureMin = 13.3f)
    private val twice = Text(small = 32.8f, figure = 59.4f, figureMin = 13.3f)

    private val oneRow = 62
    private val twoRows = 135

    @Test
    fun anUnknownHeightKeepsEveryLine() {
        val fit = PriceWidgetFit.lines(0, usual.figure, usual.small, usual.small)
        assertTrue(fit.title)
        assertTrue(fit.footer)
    }

    @Test
    fun withoutACreditOneRowKeepsTheTitleAndTheFigure() {
        val fit = PriceWidgetFit.lines(oneRow, usual.figure, usual.small, null)
        assertTrue(fit.title)
        assertFalse(fit.footer)
        assertTrue(PriceWidgetFit.lines(twoRows, usual.figure, usual.small, null).footer)
    }

    @Test
    fun oneRowKeepsTheFigureAndTheCreditWhole() {
        for (text in listOf(usual, twice)) {
            // The most the credit may take beside the figure at its
            // smallest; its size never makes it take more.
            val credit = minOf(text.small, PriceWidgetFit.creditRoomDp(oneRow, text.figureMin))
            val fit = PriceWidgetFit.lines(oneRow, text.figure, text.small, credit)
            assertFalse(fit.title)
            assertFalse(fit.footer)
            val room = PriceWidgetFit.figureRoomDp(oneRow, fit, text.small, credit)
            assertTrue("figure room $room", room >= text.figureMin - 0.001f)
        }
    }

    @Test
    fun theCreditAtItsMostLeavesTheFigureItsSmallest() {
        for (height in listOf(oneRow, 80, 104, twoRows)) {
            val credit = PriceWidgetFit.creditRoomDp(height, usual.figureMin)
            val fit = PriceWidgetFit.Lines(title = false, footer = false)
            assertEquals(
                usual.figureMin,
                PriceWidgetFit.figureRoomDp(height, fit, usual.small, credit),
                0.001f,
            )
        }
    }

    @Test
    fun twoRowsShowEveryLineAtTheUsualSize() {
        val fit = PriceWidgetFit.lines(twoRows, usual.figure, usual.small, usual.small)
        assertTrue(fit.title)
        assertTrue(fit.footer)
        assertTrue(PriceWidgetFit.figureRoomDp(twoRows, fit, usual.small, usual.small) >= usual.figure)
    }

    @Test
    fun atTwiceTheSizeTwoRowsKeepTheFigureWholeBesideTheCredit() {
        val credit = twice.small
        val fit = PriceWidgetFit.lines(twoRows, twice.figure, twice.small, credit)
        // The title, then the time, give way to the figure at its largest.
        assertFalse(fit.footer)
        assertFalse(fit.title)
        val room = PriceWidgetFit.figureRoomDp(twoRows, fit, twice.small, credit)
        assertTrue("figure room $room", room >= twice.figure)
    }
}
