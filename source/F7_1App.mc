using Toybox.Application;
using Toybox.Background;
using Toybox.System;
using Toybox.Time;
using Toybox.WatchUi;

class F7_1App extends Application.AppBase {

    var _view;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        _view = new F7_1View();
        // Register only if nothing is pending — avoids overwriting an immediate event
        // that was just registered by _updateBackgroundImmediate() in settings
        var source = AppSettings.getWeatherSource();
        if (source == 1 && Background.getTemporalEventRegisteredTime() == null) {
            System.println("[APP-FG] getInitialView: no event pending, registering OM interval");
            _updateBackground();
        } else if (source == 0 && Background.getTemporalEventRegisteredTime() != null) {
            System.println("[APP-FG] getInitialView: Garmin weather, deleting stale OM event");
            Background.deleteTemporalEvent();
        }
        return [ _view ];
    }

    function getServiceDelegate() {
        return [ new OpenMeteoBackground() ];
    }

    function onBackgroundData(data) {
        System.println("[APP-FG] onBackgroundData: " + data);
        if (_view != null) {
            _view.lastWeatherMin = -1;  // force cache reload from Storage on next onUpdate
        }
        _updateBackground();
        WatchUi.requestUpdate();
    }

    function getSettingsView() {
        return [ new SettingsMenuView(), new SettingsMenuDelegate() ];
    }

    function onSettingsChanged() {
        _updateBackground();
        if (_view != null) {
            _view.loadSettings();
            _view.lastWeatherMin = -1;  // force weather cache reload right away, not on next minute tick
        }
        WatchUi.requestUpdate();
    }

    function _updateBackground() {
        var source = AppSettings.getWeatherSource();
        if (source == 1) {
            var intervalMins = AppSettings.getWeatherInterval();
            var intervalSecs = intervalMins * 60;
            System.println("[APP-FG] _updateBackground: registering OM temporal event every " + intervalSecs + "s (" + intervalMins + " min)");
            Background.registerForTemporalEvent(new Time.Duration(intervalSecs));
        } else {
            if (Background.getTemporalEventRegisteredTime() != null) {
                System.println("[APP-FG] _updateBackground: Garmin weather selected, deleting temporal event");
                Background.deleteTemporalEvent();
            } else {
                System.println("[APP-FG] _updateBackground: Garmin weather selected, no event to delete");
            }
        }
    }

    // Trigger an immediate BG fetch (1s delay). Called when weather-related settings change.
    // On device the OS may clamp to 300s minimum; in simulator fires in ~1s.
    // After BG runs, onBackgroundData re-registers the normal interval.
    function _updateBackgroundImmediate() {
        var source = AppSettings.getWeatherSource();
        if (source == 1) {
            System.println("[APP-FG] _updateBackgroundImmediate: scheduling immediate OM fetch (1s)");
            Background.registerForTemporalEvent(new Time.Duration(1));
        } else {
            if (Background.getTemporalEventRegisteredTime() != null) {
                System.println("[APP-FG] _updateBackgroundImmediate: switched to Garmin, deleting OM event");
                Background.deleteTemporalEvent();
            }
        }
    }
}
