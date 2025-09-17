package com.outsystems.plugins.rpsgame;

import android.graphics.Color;

public enum RPSGesture {
    ROCK("Rock", Color.RED),
    PAPER("Paper", Color.GREEN),
    SCISSORS("Scissors", Color.BLUE),
    UNKNOWN("Unknown", Color.GRAY);
    
    private final String displayName;
    private final int color;
    
    RPSGesture(String displayName, int color) {
        this.displayName = displayName;
        this.color = color;
    }
    
    public String getDisplayName() {
        return displayName;
    }
    
    public int getColor() {
        return color;
    }
}