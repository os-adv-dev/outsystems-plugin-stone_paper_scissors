package com.outsystems.plugins.rpsgame;

import android.graphics.RectF;
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark;
import java.util.List;

public class HandDetection {
    public final RPSGesture gesture;
    public final RectF boundingBox;
    public final List<NormalizedLandmark> landmarks;
    public final String handedness;
    public final float confidence;
    
    public HandDetection(RPSGesture gesture, 
                        RectF boundingBox, 
                        List<NormalizedLandmark> landmarks, 
                        String handedness, 
                        float confidence) {
        this.gesture = gesture;
        this.boundingBox = boundingBox;
        this.landmarks = landmarks;
        this.handedness = handedness;
        this.confidence = confidence;
    }
}