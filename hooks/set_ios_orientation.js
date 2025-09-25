#!/usr/bin/env node

/**
 * Simple Cordova Hook: Set iOS app to Landscape Left orientation only
 * Uses string replacement instead of plist parsing
 */

const fs = require('fs');
const path = require('path');

module.exports = function(context) {
    console.log('Setting iOS orientation to Landscape Left only...');
    
    const platformRoot = path.join(context.opts.projectRoot, 'platforms', 'ios');
    
    // Find .xcodeproj directory to get app name
    const appName = getAppName(platformRoot);
    if (!appName) {
        console.error('Could not determine app name');
        return;
    }
    
    const infoPlistPath = path.join(platformRoot, appName, `${appName}-Info.plist`);
    
    if (!fs.existsSync(infoPlistPath)) {
        console.error(`Info.plist not found at: ${infoPlistPath}`);
        return;
    }
    
    try {
        let infoPlistContent = fs.readFileSync(infoPlistPath, 'utf8');
        
        // Replace UISupportedInterfaceOrientations array with Landscape Left only
        const orientationRegex = /<key>UISupportedInterfaceOrientations<\/key>\s*<array>[\s\S]*?<\/array>/g;
        const landscapeLeftOnly = `<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationLandscapeLeft</string>
	</array>`;
        
        infoPlistContent = infoPlistContent.replace(orientationRegex, landscapeLeftOnly);
        
        // Also handle iPad orientations if present
        const iPadOrientationRegex = /<key>UISupportedInterfaceOrientations~ipad<\/key>\s*<array>[\s\S]*?<\/array>/g;
        const iPadLandscapeLeftOnly = `<key>UISupportedInterfaceOrientations~ipad</key>
	<array>
		<string>UIInterfaceOrientationLandscapeLeft</string>
	</array>`;
        
        infoPlistContent = infoPlistContent.replace(iPadOrientationRegex, iPadLandscapeLeftOnly);
        
        fs.writeFileSync(infoPlistPath, infoPlistContent, 'utf8');
        
        console.log('✅ Successfully set iOS orientation to Landscape Left only');
        console.log(`Updated: ${infoPlistPath}`);
        
    } catch (error) {
        console.error('Error updating Info.plist:', error);
    }
};

function getAppName(platformRoot) {
    if (!fs.existsSync(platformRoot)) {
        return null;
    }
    
    const files = fs.readdirSync(platformRoot);
    for (let file of files) {
        if (file.endsWith('.xcodeproj')) {
            return file.replace('.xcodeproj', '');
        }
    }
    
    return null;
}
