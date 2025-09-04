var exec = require('cordova/exec');

exports.showGameScreen = function(success, error) {
    exec(success, error, 'RPSGamePlugin', 'showGameScreen', []);
};