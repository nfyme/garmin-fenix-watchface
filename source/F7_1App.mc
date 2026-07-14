using Toybox.Application;
using Toybox.Background;
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
            _updateBackground();
        } else if (source == 0 && Background.getTemporalEventRegisteredTime() != null) {
            Background.deleteTemporalEvent();
        }
        return [ _view ];
    }

    function getServiceDelegate() {
        return [ new OpenMeteoBackground() ];
    }

    function onBackgroundData(data) {
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
        // Системный Settings-экран (симулятор "App Settings" / Garmin Connect
        // на телефоне) меняет Properties и вызывает только этот колбэк — минуя
        // наш кастомный Menu2 и его BgTriggerPickerDelegate. Поэтому именно
        // здесь, а не через обычный _updateBackground(), нужен immediate-fetch,
        // иначе смена weatherSource/locationSource через системные Settings
        // молча ждёт полный интервал (5-60 мин) вместо мгновенного обновления.
        _updateBackgroundImmediate();
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
            Background.registerForTemporalEvent(new Time.Duration(intervalSecs));
        } else if (Background.getTemporalEventRegisteredTime() != null) {
            Background.deleteTemporalEvent();
        }
    }

    // Trigger a near-immediate BG fetch. 5 minutes is the OS-enforced minimum
    // period (Time.Duration(1) throws "Background event period cannot be
    // less than 5 minutes" — the simulator enforces this hard, real devices
    // used to silently clamp it, so don't rely on that). After BG runs,
    // onBackgroundData re-registers the normal interval.
    function _updateBackgroundImmediate() {
        var source = AppSettings.getWeatherSource();
        if (source == 1) {
            Background.registerForTemporalEvent(new Time.Duration(300));
        } else if (Background.getTemporalEventRegisteredTime() != null) {
            Background.deleteTemporalEvent();
        }
    }
}
