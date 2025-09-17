package com.outsystems.plugins.rpsgame;

import android.content.Intent;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CallbackContext;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONException;

public class RPSGamePlugin extends CordovaPlugin {

    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
        if ("showGameScreen".equals(action)) {
            this.showGameScreen(callbackContext);
            return true;
        }
        return false;
    }

    private void showGameScreen(CallbackContext callbackContext) {
        cordova.getActivity().runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    Intent intent = new Intent(cordova.getActivity(), RPSDetectionActivity.class);
                    cordova.getActivity().startActivity(intent);
                    
                    PluginResult result = new PluginResult(PluginResult.Status.OK);
                    callbackContext.sendPluginResult(result);
                } catch (Exception e) {
                    PluginResult result = new PluginResult(PluginResult.Status.ERROR, "Failed to load Activity: " + e.getMessage());
                    callbackContext.sendPluginResult(result);
                }
            }
        });
    }
}