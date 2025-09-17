package com.outsystems.plugins.rpsgame;

import android.Manifest;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import android.os.Bundle;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Log;
import android.util.Size;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.ImageProxy;
import androidx.camera.core.Preview;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.lifecycle.LifecycleOwner;

import com.google.common.util.concurrent.ListenableFuture;
import com.google.mediapipe.framework.image.BitmapImageBuilder;
import com.google.mediapipe.framework.image.MPImage;
import com.google.mediapipe.tasks.core.BaseOptions;
import com.google.mediapipe.tasks.vision.core.RunningMode;
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker;
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult;
import com.google.mediapipe.tasks.components.containers.Category;
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class RPSDetectionActivity extends AppCompatActivity {

    private static final String TAG = "RPSDetectionActivity";
    private static final int CAMERA_PERMISSION_REQUEST = 100;

    // UI Components
    private PreviewView previewView;
    private TextView player1Label;
    private TextView player2Label;
    private TextView winnerLabel;
    private TextView instructionsLabel;
    private ImageView handImage;
    private View playersBgView;
    private OverlayView overlayView;

    // Camera
    private ListenableFuture<ProcessCameraProvider> cameraProviderFuture;
    private ProcessCameraProvider cameraProvider;
    private ImageAnalysis imageAnalysis;
    private ExecutorService backgroundExecutor;

    // MediaPipe
    private HandLandmarker handLandmarker;
    private int frameWidth = 0;
    private int frameHeight = 0;
    private List<HandDetection> lastDetections = new ArrayList<>();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Get the app's package name and use it to find resources
        String packageName = getApplicationContext().getPackageName();
        int layoutId = getResources().getIdentifier("activity_rps_detection", "layout", packageName);
        setContentView(layoutId);

        // Keep screen on
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        initializeViews();
        setupUI();

        // Check camera permission
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            setupMediaPipe();
            setupCamera();
        } else {
            ActivityCompat.requestPermissions(this, new String[]{Manifest.permission.CAMERA}, CAMERA_PERMISSION_REQUEST);
        }
    }

    private void initializeViews() {
        String packageName = getApplicationContext().getPackageName();

        previewView = findViewById(getResources().getIdentifier("previewView", "id", packageName));
        player1Label = findViewById(getResources().getIdentifier("player1Label", "id", packageName));
        player2Label = findViewById(getResources().getIdentifier("player2Label", "id", packageName));
        winnerLabel = findViewById(getResources().getIdentifier("winnerLabel", "id", packageName));
        instructionsLabel = findViewById(getResources().getIdentifier("instructionsLabel", "id", packageName));
        handImage = findViewById(getResources().getIdentifier("handImage", "id", packageName));
        playersBgView = findViewById(getResources().getIdentifier("playersBgView", "id", packageName));
        overlayView = findViewById(getResources().getIdentifier("overlayView", "id", packageName));
    }

    private void setupUI() {
        instructionsLabel.setText("Show your hands to play Rock, Paper, and Scissors!");
        player1Label.setText("Player 1: --");
        player2Label.setText("Player 2: --");
        winnerLabel.setText("");

        // Hide player labels initially
        playersBgView.setVisibility(View.GONE);

        // Auto-hide instructions after 3 seconds
        new Handler().postDelayed(() -> {
            instructionsLabel.animate().alpha(0f).setDuration(1000).start();
            handImage.animate().alpha(0f).setDuration(1000).withEndAction(() -> {
                instructionsLabel.setVisibility(View.GONE);
                handImage.setVisibility(View.GONE);
                playersBgView.setVisibility(View.VISIBLE);
            }).start();
        }, 3000);
    }

    private void setupMediaPipe() {
        try {
            BaseOptions baseOptions = BaseOptions.builder()
                    .setModelAssetPath("models/hand_landmarker.task")
                    .build();

            HandLandmarker.HandLandmarkerOptions options = HandLandmarker.HandLandmarkerOptions.builder()
                    .setBaseOptions(baseOptions)
                    .setRunningMode(RunningMode.IMAGE) // Use IMAGE mode instead of LIVE_STREAM
                    .setNumHands(2)
                    .setMinHandDetectionConfidence(0.7f)
                    .setMinHandPresenceConfidence(0.7f)
                    .setMinTrackingConfidence(0.5f)
                    .build();

            handLandmarker = HandLandmarker.createFromOptions(this, options);
        } catch (Exception e) {
            Log.e(TAG, "Failed to create HandLandmarker", e);
            Toast.makeText(this, "Failed to initialize hand detection", Toast.LENGTH_LONG).show();
        }
    }

    private void setupCamera() {
        backgroundExecutor = Executors.newSingleThreadExecutor();
        cameraProviderFuture = ProcessCameraProvider.getInstance(this);

        cameraProviderFuture.addListener(() -> {
            try {
                cameraProvider = cameraProviderFuture.get();
                bindPreview(cameraProvider);
            } catch (ExecutionException | InterruptedException e) {
                Log.e(TAG, "Camera provider initialization failed", e);
            }
        }, ContextCompat.getMainExecutor(this));
    }

    private void bindPreview(@NonNull ProcessCameraProvider cameraProvider) {
        Preview preview = new Preview.Builder().build();
        preview.setSurfaceProvider(previewView.getSurfaceProvider());

        CameraSelector cameraSelector = new CameraSelector.Builder()
                .requireLensFacing(CameraSelector.LENS_FACING_FRONT)
                .build();

        imageAnalysis = new ImageAnalysis.Builder()
                .setTargetResolution(new Size(640, 480))
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build();

        imageAnalysis.setAnalyzer(backgroundExecutor, this::analyzeImage);

        cameraProvider.unbindAll();
        cameraProvider.bindToLifecycle(
                (LifecycleOwner) this,
                cameraSelector,
                preview,
                imageAnalysis
        );
    }

    private void analyzeImage(ImageProxy imageProxy) {
        if (handLandmarker == null) {
            imageProxy.close();
            return;
        }

        frameWidth = imageProxy.getWidth();
        frameHeight = imageProxy.getHeight();

        // Convert ImageProxy to Bitmap
        Bitmap bitmap = imageProxy.toBitmap();

        // Convert to MPImage
        MPImage mpImage = new BitmapImageBuilder(bitmap).build();

        try {
            // Use detect() instead of detectAsync() since we're in IMAGE mode
            HandLandmarkerResult result = handLandmarker.detect(mpImage);

            // Process result on main thread
            runOnUiThread(() -> processResult(result));

        } catch (Exception e) {
            Log.e(TAG, "Hand detection error", e);
        }

        imageProxy.close();
    }

    private void processResult(HandLandmarkerResult result) {
        if (result.landmarks().isEmpty()) {
            lastDetections.clear();
            updateUI(lastDetections);
            overlayView.clear();
            return;
        }

        List<HandDetection> detections = new ArrayList<>();

        for (int i = 0; i < result.landmarks().size(); i++) {
            List<NormalizedLandmark> landmarks = result.landmarks().get(i);

            // Simplified - no handedness detection for now
            String handLabel = "Hand " + (i + 1);
            float confidence = 1.0f;

            RPSGesture gesture = classifyGesture(landmarks);
            RectF boundingBox = getBoundingBox(landmarks);

            Log.d(TAG, "Before sorting - Detection " + i + ": " + gesture.getDisplayName() +
                    " at box left=" + boundingBox.left + " right=" + boundingBox.right);

            detections.add(new HandDetection(gesture, boundingBox, landmarks, handLabel, confidence));
        }

        // Sort by flipped X coordinates to match what user sees on screen
        // After flipping: leftmost on screen = Player 1, rightmost on screen = Player 2
        Collections.sort(detections, (a, b) -> {
            float flippedALeft = 1.0f - a.boundingBox.right;  // Flip A's X
            float flippedBLeft = 1.0f - b.boundingBox.right;  // Flip B's X
            return Float.compare(flippedALeft, flippedBLeft);
        });

        // Debug after sorting
        for (int i = 0; i < detections.size(); i++) {
            HandDetection det = detections.get(i);
            float flippedLeft = 1.0f - det.boundingBox.right;
            Log.d(TAG, "After sorting - Player " + (i + 1) + ": " + det.gesture.getDisplayName() +
                    " at flipped position=" + flippedLeft);
        }

        lastDetections = detections;
        updateUI(detections);
        overlayView.setDetections(detections);
    }

    private RPSGesture classifyGesture(List<NormalizedLandmark> landmarks) {
        if (landmarks.size() < 21) return RPSGesture.UNKNOWN;

        boolean thumb = isThumbExtended(landmarks, 2, 3, 4);
        boolean index = isFingerExtended(landmarks, 5, 6, 7);
        boolean middle = isFingerExtended(landmarks, 9, 10, 11);
        boolean ring = isFingerExtended(landmarks, 13, 14, 15);
        boolean pinky = isFingerExtended(landmarks, 17, 18, 19);

        if (index && middle && !ring && !pinky) return RPSGesture.SCISSORS;

        int extendedCount = 0;
        if (thumb) extendedCount++;
        if (index) extendedCount++;
        if (middle) extendedCount++;
        if (ring) extendedCount++;
        if (pinky) extendedCount++;

        if (extendedCount >= 4) return RPSGesture.PAPER;
        if (extendedCount <= 1) return RPSGesture.ROCK;

        return RPSGesture.UNKNOWN;
    }

    private boolean isFingerExtended(List<NormalizedLandmark> landmarks, int mcp, int pip, int dip) {
        return getAngle(landmarks.get(mcp), landmarks.get(pip), landmarks.get(dip)) >= 160.0;
    }

    private boolean isThumbExtended(List<NormalizedLandmark> landmarks, int mcp, int ip, int tip) {
        return getAngle(landmarks.get(mcp), landmarks.get(ip), landmarks.get(tip)) >= 160.0;
    }

    private double getAngle(NormalizedLandmark a, NormalizedLandmark b, NormalizedLandmark c) {
        double abX = a.x() - b.x();
        double abY = a.y() - b.y();
        double cbX = c.x() - b.x();
        double cbY = c.y() - b.y();

        double dot = abX * cbX + abY * cbY;
        double magAB = Math.sqrt(abX * abX + abY * abY);
        double magCB = Math.sqrt(cbX * cbX + cbY * cbY);

        if (magAB * magCB == 0) return 0;

        double cosAngle = Math.max(-1, Math.min(1, dot / (magAB * magCB)));
        return Math.acos(cosAngle) * 180.0 / Math.PI;
    }

    private RectF getBoundingBox(List<NormalizedLandmark> landmarks) {
        float minX = Float.MAX_VALUE, minY = Float.MAX_VALUE;
        float maxX = Float.MIN_VALUE, maxY = Float.MIN_VALUE;

        // Find the bounding box in normalized coordinates (0.0 to 1.0)
        for (NormalizedLandmark landmark : landmarks) {
            minX = Math.min(minX, landmark.x());
            minY = Math.min(minY, landmark.y());
            maxX = Math.max(maxX, landmark.x());
            maxY = Math.max(maxY, landmark.y());
        }

        // Add some padding in normalized space
        float padding = 0.05f; // 5% padding
        minX = Math.max(0.0f, minX - padding);
        minY = Math.max(0.0f, minY - padding);
        maxX = Math.min(1.0f, maxX + padding);
        maxY = Math.min(1.0f, maxY + padding);

        // Return normalized coordinates - scaling will be done in overlay
        return new RectF(minX, minY, maxX, maxY);
    }

    private void updateUI(List<HandDetection> detections) {
        // Sort detections left to right to assign players consistently
        List<HandDetection> sortedDetections = new ArrayList<>(detections);
        Collections.sort(sortedDetections, (a, b) -> Float.compare(a.boundingBox.left, b.boundingBox.left));

        if (sortedDetections.size() >= 2) {
            // Reverse the order for top labels and game logic to match bounding boxes
            HandDetection p1 = sortedDetections.get(1); // What should be Player 1 (left side)
            HandDetection p2 = sortedDetections.get(0); // What should be Player 2 (right side)

            // Debug logging to check player assignments
            Log.d(TAG, "Player 1 (left): " + p1.gesture.getDisplayName());
            Log.d(TAG, "Player 2 (right): " + p2.gesture.getDisplayName());

            player1Label.setText("Player 1: " + p1.gesture.getDisplayName());
            player2Label.setText("Player 2: " + p2.gesture.getDisplayName());

            String winner = determineWinner(p1.gesture, p2.gesture);
            if (winner != null) {
                Log.d(TAG, "Winner: " + winner);
            }
            winnerLabel.setText(winner != null ? winner : "");

        } else if (sortedDetections.size() == 1) {
            // Show the detected gesture for Player 1, keep Player 2 as waiting
            player1Label.setText("Player 1: " + sortedDetections.get(0).gesture.getDisplayName());
            player2Label.setText("Player 2: Waiting...");
            winnerLabel.setText(""); // No winner with only one player
        } else {
            // No hands detected
            player1Label.setText("Player 1: --");
            player2Label.setText("Player 2: --");
            winnerLabel.setText("");
        }
    }

    private String determineWinner(RPSGesture g1, RPSGesture g2) {
        if (g1 == g2) return "It's a Tie!";

        // Rock Paper Scissors rules:
        // Rock beats Scissors
        // Paper beats Rock
        // Scissors beats Paper
        switch (g1) {
            case ROCK:
                return g2 == RPSGesture.SCISSORS ? "Player 1 Wins!" : "Player 2 Wins!";
            case PAPER:
                return g2 == RPSGesture.ROCK ? "Player 1 Wins!" : "Player 2 Wins!";
            case SCISSORS:
                return g2 == RPSGesture.PAPER ? "Player 1 Wins!" : "Player 2 Wins!";
            default:
                return null;
        }
    }

    private void resetGame() {
        lastDetections.clear();
        // overlayView.clear(); // Disabled for now
        player1Label.setText("Player 1: --");
        player2Label.setText("Player 2: --");
        winnerLabel.setText("");
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == CAMERA_PERMISSION_REQUEST) {
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                setupMediaPipe();
                setupCamera();
            } else {
                Toast.makeText(this, "Camera permission is required", Toast.LENGTH_LONG).show();
                finish();
            }
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (backgroundExecutor != null) {
            backgroundExecutor.shutdown();
        }
        if (cameraProvider != null) {
            cameraProvider.unbindAll();
        }
        if (handLandmarker != null) {
            handLandmarker.close();
        }
    }
}