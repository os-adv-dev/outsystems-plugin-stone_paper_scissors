#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

module.exports = function(context) {
    const platformRoot = path.join(context.opts.projectRoot, 'platforms');
    const androidPlatformPath = path.join(platformRoot, 'android');
    
    // Only run for Android platform
    if (!fs.existsSync(androidPlatformPath)) {
        console.log('Android platform not found, skipping asset copy');
        return;
    }
    
    // Source and target paths
    const pluginDir = context.opts.plugin.dir || context.opts.projectRoot;
    const sourceFile = path.join(pluginDir, 'src', 'models', 'hand_landmarker.task');
    const targetDir = path.join(androidPlatformPath, 'app', 'src', 'main', 'assets', 'models');
    const targetFile = path.join(targetDir, 'hand_landmarker.task');
    
    try {
        // Check if source file exists
        if (!fs.existsSync(sourceFile)) {
            console.error('Source model file not found:', sourceFile);
            return;
        }
        
        // Create target directory if it doesn't exist
        if (!fs.existsSync(targetDir)) {
            fs.mkdirSync(targetDir, { recursive: true });
            console.log('Created assets directory:', targetDir);
        }
        
        // Copy the model file
        fs.copyFileSync(sourceFile, targetFile);
        console.log('Successfully copied model file to:', targetFile);
        
    } catch (error) {
        console.error('Error copying model file:', error);
    }
};