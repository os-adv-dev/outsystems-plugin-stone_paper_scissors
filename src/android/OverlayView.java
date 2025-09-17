package com.outsystems.plugins.rpsgame;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.util.AttributeSet;
import android.view.View;

import java.util.ArrayList;
import java.util.List;

public class OverlayView extends View {

    private List<HandDetection> detections = new ArrayList<>();
    private Paint boxPaint;
    private Paint textPaint;
    private Paint textBgPaint;

    public OverlayView(Context context) {
        super(context);
        init();
    }

    public OverlayView(Context context, AttributeSet attrs) {
        super(context, attrs);
        init();
    }

    public OverlayView(Context context, AttributeSet attrs, int defStyleAttr) {
        super(context, attrs, defStyleAttr);
        init();
    }

    private void init() {
        boxPaint = new Paint();
        boxPaint.setStyle(Paint.Style.STROKE);
        boxPaint.setStrokeWidth(6f);

        textPaint = new Paint();
        textPaint.setColor(Color.WHITE);
        textPaint.setTextSize(32f);
        textPaint.setAntiAlias(true);
        textPaint.setTextAlign(Paint.Align.CENTER);
        textPaint.setFakeBoldText(true);

        textBgPaint = new Paint();
        textBgPaint.setStyle(Paint.Style.FILL);
        textBgPaint.setAntiAlias(true);
    }

    public void setDetections(List<HandDetection> detections) {
        this.detections = new ArrayList<>(detections);
        invalidate();
    }

    public void clear() {
        detections.clear();
        invalidate();
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);

        // Get the actual view dimensions
        float viewWidth = getWidth();
        float viewHeight = getHeight();

        if (viewWidth <= 0 || viewHeight <= 0) return;

        for (int i = 0; i < detections.size(); i++) {
            HandDetection detection = detections.get(i);

            // Convert normalized coordinates (0.0-1.0) to screen pixels
            // The bounding box from MediaPipe is in normalized coordinates
            RectF normalizedBox = detection.boundingBox;

            // Mirror the X coordinates to match the camera preview
            RectF scaledBox = new RectF(
                    (1.0f - normalizedBox.right) * viewWidth,  // Flip X: right becomes left
                    normalizedBox.top * viewHeight,
                    (1.0f - normalizedBox.left) * viewWidth,   // Flip X: left becomes right
                    normalizedBox.bottom * viewHeight
            );

            // Draw bounding box
            boxPaint.setColor(detection.gesture.getColor());
            canvas.drawRoundRect(scaledBox, 16f, 16f, boxPaint);

            // Create label text - use only our player assignment, not MediaPipe handedness
            int confidence = Math.round(detection.confidence * 100);
            String text = String.format("P%d: %s (%d%%)",
                    i + 1, detection.gesture.getDisplayName(), confidence);

            // Calculate text position - above the bounding box
            float textX = scaledBox.centerX();
            float textY = Math.max(textPaint.getTextSize() + 20f, scaledBox.top - 12f);

            // Draw text background
            Paint.FontMetrics fontMetrics = textPaint.getFontMetrics();
            float textWidth = textPaint.measureText(text);

            RectF textBg = new RectF(
                    textX - textWidth / 2 - 12f,
                    textY + fontMetrics.top - 6f,
                    textX + textWidth / 2 + 12f,
                    textY + fontMetrics.bottom + 6f
            );

            textBgPaint.setColor(detection.gesture.getColor());
            textBgPaint.setAlpha(200); // Semi-transparent like iOS
            canvas.drawRoundRect(textBg, 6f, 6f, textBgPaint);

            // Draw text
            canvas.drawText(text, textX, textY, textPaint);
        }
    }
}