using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Application;

// ============================================================================
// SETTINGS STORAGE
// ============================================================================
class AppSettings {

    static var WEATHER_INTERVALS = [5, 10, 15, 30, 60];

    // Минимальный % вероятности осадков, ниже которого кольцо для часа не рисуется
    static var RING_MIN_PRECIP_VALUES = [5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100];
    static var RING_MIN_PRECIP_LABELS = ["5%", "10%", "20%", "30%", "40%", "50%", "60%", "70%", "80%", "90%", "100%"];

    static function getRingMinPrecip() {
        var idx = Application.Properties.getValue("ringMinPrecip");
        if (idx == null || idx < 0 || idx >= RING_MIN_PRECIP_VALUES.size()) { idx = 0; }
        return RING_MIN_PRECIP_VALUES[idx];
    }

    static var WEEKEND_COLORS = [
        0xAA0000,
        0xFF5500,
        0x00AA00,
        0x0055FF,
        Graphics.COLOR_LT_GRAY
    ];

    static var TIME_COLORS = [
        Graphics.COLOR_WHITE,
        0xFF2222,
        0xFF5500,
        0x00AA00,
        0x0055FF,
        0xFFFF00,
        Graphics.COLOR_LT_GRAY
    ];

    static var TIME_COLOR_NAMES  = ["White", "Red", "Orange", "Green", "Blue", "Yellow", "Gray"];
    static var COLON_COLOR_NAMES = ["White", "Red", "Orange", "Green", "Blue", "Yellow", "Gray", "Hidden"];

    static function getHourColor() {
        var idx = Application.Properties.getValue("hourColor");
        if (idx == null || idx < 0 || idx >= TIME_COLORS.size()) { idx = 0; }
        return TIME_COLORS[idx];
    }

    static function getMinuteColor() {
        var idx = Application.Properties.getValue("minuteColor");
        if (idx == null || idx < 0 || idx >= TIME_COLORS.size()) { idx = 4; }
        return TIME_COLORS[idx];
    }

    static function getColonColor() {
        var idx = Application.Properties.getValue("colonColor");
        if (idx == null || idx < 0 || idx >= TIME_COLORS.size() + 1) { idx = 0; }
        if (idx == 7) { return -1; } // -1 = скрыть
        return TIME_COLORS[idx];
    }

    static var WEATHER_SOURCES   = ["Garmin", "Open-Meteo"];
    static var LOCATION_SOURCES  = ["GPS", "Garmin Weather"];
    static var WEEKEND_COLOR_NAMES = ["Red", "Orange", "Green", "Blue", "Gray"];
    static var BLOCK_NAMES = ["Calendar", "Sport"];

    static function getWeatherInterval() {
        var idx = Application.Properties.getValue("weatherInterval");
        if (idx == null || idx < 0 || idx >= WEATHER_INTERVALS.size()) { idx = 2; }
        return WEATHER_INTERVALS[idx];
    }

    static function getWeekendColor() {
        var idx = Application.Properties.getValue("weekendColor");
        if (idx == null || idx < 0 || idx >= WEEKEND_COLORS.size()) { idx = 0; }
        return WEEKEND_COLORS[idx];
    }

    static function getBottomBlock() {
        var val = Application.Properties.getValue("bottomBlock");
        if (val == null) { val = 0; }
        return val;
    }

    static function getPrecipRing() {
        var val = Application.Properties.getValue("precipRing");
        if (val == null) { val = true; }
        return val;
    }

    static var DANGER_RING_MODES = ["Off", "Inside", "Outside"];

    // 0 = Off, 1 = Inside (чуть внутри основного кольца), 2 = Outside (у самого края экрана)
    static function getDangerRingMode() {
        var val = Application.Properties.getValue("dangerRingMode");
        if (val == null) { val = 1; }
        return val;
    }

    static function getPrecipForecast() {
        var val = Application.Properties.getValue("precipForecast");
        if (val == null) { val = true; }
        return val;
    }

    static function getWeatherDisplay() {
        var val = Application.Properties.getValue("weatherDisplay");
        if (val == null) { val = true; }
        return val;
    }

    static function getHeartRate() {
        var val = Application.Properties.getValue("heartRate");
        if (val == null) { val = true; }
        return val;
    }

    static function getWeatherSource() {
        var val = Application.Properties.getValue("weatherSource");
        if (val == null) { val = 0; }
        return val;
    }

    static function getLocationSource() {
        var val = Application.Properties.getValue("locationSource");
        if (val == null) { val = 0; }
        return val;
    }

    static function getWeatherDemoMode() {
        var val = Application.Properties.getValue("weatherDemoMode");
        if (val == null) { val = false; }
        return val;
    }
}

// ============================================================================
// MAIN SETTINGS MENU
// ============================================================================
class SettingsMenuView extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({ :title => "Dark Watch" });

        var wsIdx = Application.Properties.getValue("weatherSource");
        if (wsIdx == null) { wsIdx = 0; }
        var lsIdx = Application.Properties.getValue("locationSource");
        if (lsIdx == null) { lsIdx = 0; }

        Menu2.addItem(new WatchUi.MenuItem(
            "Weather source",
            AppSettings.WEATHER_SOURCES[wsIdx],
            :weatherSource,
            {}
        ));

        Menu2.addItem(new WatchUi.MenuItem(
            "Location source",
            AppSettings.LOCATION_SOURCES[lsIdx],
            :locationSource,
            {}
        ));


        var wIdx = Application.Properties.getValue("weatherInterval");
        if (wIdx == null) { wIdx = 2; }

        var cIdx = Application.Properties.getValue("weekendColor");
        if (cIdx == null) { cIdx = 0; }

        var bIdx = Application.Properties.getValue("bottomBlock");
        if (bIdx == null) { bIdx = 0; }

        var hcIdx = Application.Properties.getValue("hourColor");
        if (hcIdx == null) { hcIdx = 0; }

        var mcIdx = Application.Properties.getValue("minuteColor");
        if (mcIdx == null) { mcIdx = 4; }

        var ccIdx = Application.Properties.getValue("colonColor");
        if (ccIdx == null) { ccIdx = 0; }

        Menu2.addItem(new WatchUi.MenuItem(
            "Weather update",
            AppSettings.WEATHER_INTERVALS[wIdx] + " min",
            :weatherInterval,
            {}
        ));

        Menu2.addItem(new WatchUi.MenuItem(
            "Weekend color",
            AppSettings.WEEKEND_COLOR_NAMES[cIdx],
            :weekendColor,
            {}
        ));

                Menu2.addItem(new WatchUi.MenuItem(
            "Hour color",
            AppSettings.TIME_COLOR_NAMES[hcIdx],
            :hourColor,
            {}
        ));

        Menu2.addItem(new WatchUi.MenuItem(
            "Minute color",
            AppSettings.TIME_COLOR_NAMES[mcIdx],
            :minuteColor,
            {}
        ));

        Menu2.addItem(new WatchUi.MenuItem(
            "Colon color",
            AppSettings.COLON_COLOR_NAMES[ccIdx],
            :colonColor,
            {}
        ));

        Menu2.addItem(new WatchUi.MenuItem(
            "Bottom block",
            AppSettings.BLOCK_NAMES[bIdx],
            :bottomBlock,
            {}
        ));
        Menu2.addItem(new WatchUi.ToggleMenuItem(
            "Precip ring",
            null,
            :precipRing,
            AppSettings.getPrecipRing(),
            {}
        ));

        var drmIdx = Application.Properties.getValue("dangerRingMode");
        if (drmIdx == null) { drmIdx = 1; }

        Menu2.addItem(new WatchUi.MenuItem(
            "Danger ring",
            AppSettings.DANGER_RING_MODES[drmIdx],
            :dangerRingMode,
            {}
        ));

        var rmpIdx = Application.Properties.getValue("ringMinPrecip");
        if (rmpIdx == null) { rmpIdx = 0; }

        Menu2.addItem(new WatchUi.MenuItem(
            "Ring min precip",
            AppSettings.RING_MIN_PRECIP_LABELS[rmpIdx],
            :ringMinPrecip,
            {}
        ));

        Menu2.addItem(new WatchUi.ToggleMenuItem(
            "Precip forecast",
            null,
            :precipForecast,
            AppSettings.getPrecipForecast(),
            {}
        ));

        Menu2.addItem(new WatchUi.ToggleMenuItem(
            "Weather",
            null,
            :weatherDisplay,
            AppSettings.getWeatherDisplay(),
            {}
        ));

        Menu2.addItem(new WatchUi.ToggleMenuItem(
            "Heart rate",
            null,
            :heartRate,
            AppSettings.getHeartRate(),
            {}
        ));

        Menu2.addItem(new WatchUi.ToggleMenuItem(
            "Weather demo mode",
            null,
            :weatherDemoMode,
            AppSettings.getWeatherDemoMode(),
            {}
        ));



    }
}

// ============================================================================
// MAIN SETTINGS DELEGATE
// Передаём сам MenuItem в дочерний делегат — он обновит subLabel напрямую
// ============================================================================
class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        var id = item.getId();

        if (id == :weatherSource) {
            WatchUi.pushView(
                new ColorPicker("Weather source", "weatherSource", AppSettings.WEATHER_SOURCES),
                new BgTriggerPickerDelegate(item, "weatherSource", AppSettings.WEATHER_SOURCES),
                WatchUi.SLIDE_LEFT
            );
        }
        else if (id == :locationSource) {
            WatchUi.pushView(
                new ColorPicker("Location source", "locationSource", AppSettings.LOCATION_SOURCES),
                new BgTriggerPickerDelegate(item, "locationSource", AppSettings.LOCATION_SOURCES),
                WatchUi.SLIDE_LEFT
            );
        }
        else if (id == :weatherInterval) {
            WatchUi.pushView(
                new WeatherIntervalPicker(),
                new WeatherIntervalDelegate(item),
                WatchUi.SLIDE_LEFT
            );
        }
        else if (id == :weekendColor) {
            WatchUi.pushView(
                new WeekendColorPicker(),
                new WeekendColorDelegate(item),     // передаём item
                WatchUi.SLIDE_LEFT
            );
        }
        else if (id == :bottomBlock) {
            WatchUi.pushView(
                new BottomBlockPicker(),
                new BottomBlockDelegate(item),      // передаём item
                WatchUi.SLIDE_LEFT
            );
        }

        

        else if (id == :precipRing) {
            Application.Properties.setValue("precipRing",      (item as WatchUi.ToggleMenuItem).isEnabled());
        }
        else if (id == :dangerRingMode) {
            WatchUi.pushView(
                new ColorPicker("Danger ring", "dangerRingMode", AppSettings.DANGER_RING_MODES),
                new ColorPickerDelegate(item, "dangerRingMode", AppSettings.DANGER_RING_MODES),
                WatchUi.SLIDE_LEFT
            );
        }
        else if (id == :ringMinPrecip) {
            WatchUi.pushView(
                new ColorPicker("Ring min precip", "ringMinPrecip", AppSettings.RING_MIN_PRECIP_LABELS),
                new ColorPickerDelegate(item, "ringMinPrecip", AppSettings.RING_MIN_PRECIP_LABELS),
                WatchUi.SLIDE_LEFT
            );
        }
        else if (id == :precipForecast) {
            Application.Properties.setValue("precipForecast", (item as WatchUi.ToggleMenuItem).isEnabled());
        }
        else if (id == :weatherDisplay) {
            Application.Properties.setValue("weatherDisplay", (item as WatchUi.ToggleMenuItem).isEnabled());
        }
        else if (id == :heartRate) {
            Application.Properties.setValue("heartRate", (item as WatchUi.ToggleMenuItem).isEnabled());
        }
        else if (id == :weatherDemoMode) {
            Application.Properties.setValue("weatherDemoMode", (item as WatchUi.ToggleMenuItem).isEnabled());
        }

        else if (id == :hourColor) {
            WatchUi.pushView(new ColorPicker("Hour color", "hourColor", AppSettings.TIME_COLOR_NAMES),
                            new ColorPickerDelegate(item, "hourColor", AppSettings.TIME_COLOR_NAMES),
                            WatchUi.SLIDE_LEFT);
        }
        else if (id == :minuteColor) {
            WatchUi.pushView(new ColorPicker("Minute color", "minuteColor", AppSettings.TIME_COLOR_NAMES),
                            new ColorPickerDelegate(item, "minuteColor", AppSettings.TIME_COLOR_NAMES),
                            WatchUi.SLIDE_LEFT);
        }
        else if (id == :colonColor) {
            WatchUi.pushView(new ColorPicker("Colon color", "colonColor", AppSettings.COLON_COLOR_NAMES),
                            new ColorPickerDelegate(item, "colonColor", AppSettings.COLON_COLOR_NAMES),
                            WatchUi.SLIDE_LEFT);
        }
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

class ColorPicker extends WatchUi.Menu2 {
    function initialize(title, key, names) {
        Menu2.initialize({ :title => title });
        var currentIdx = Application.Properties.getValue(key);
        if (currentIdx == null) { currentIdx = 0; }
        for (var i = 0; i < names.size(); i++) {
            var label = (i == currentIdx) ? "[ " + names[i] + " ]" : names[i];
            Menu2.addItem(new WatchUi.MenuItem(label, null, i, {}));
        }
        Menu2.setFocus(currentIdx);
    }
}

// Picker delegate that also triggers an immediate BG weather fetch on confirm.
// Used for weatherSource and locationSource settings.
class BgTriggerPickerDelegate extends WatchUi.Menu2InputDelegate {
    var _parentItem;
    var _key;
    var _names;

    function initialize(parentItem, key, names) {
        Menu2InputDelegate.initialize();
        _parentItem = parentItem;
        _key        = key;
        _names      = names;
    }

    function onSelect(item) {
        var idx = item.getId();
        Application.Properties.setValue(_key, idx);
        _parentItem.setSubLabel(_names[idx]);
        (Application.getApp() as F7_1App)._updateBackgroundImmediate();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

class ColorPickerDelegate extends WatchUi.Menu2InputDelegate {
    var _parentItem;
    var _key;
    var _names;

    function initialize(parentItem, key, names) {
        Menu2InputDelegate.initialize();
        _parentItem = parentItem;
        _key        = key;
        _names      = names;
    }

    function onSelect(item) {
        var idx = item.getId();
        Application.Properties.setValue(_key, idx);
        _parentItem.setSubLabel(_names[idx]);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

// ============================================================================
// WEATHER INTERVAL PICKER
// ============================================================================
class WeatherIntervalPicker extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({ :title => "Weather update" });

        var currentIdx = Application.Properties.getValue("weatherInterval");
        if (currentIdx == null) { currentIdx = 2; }

        var labels = ["5 min", "10 min", "15 min", "30 min", "60 min"];

        for (var i = 0; i < labels.size(); i++) {
            var label = (i == currentIdx) ? "[ " + labels[i] + " ]" : labels[i];
            Menu2.addItem(new WatchUi.MenuItem(label, null, i, {}));
        }

        Menu2.setFocus(currentIdx);
    }
}

class WeatherIntervalDelegate extends WatchUi.Menu2InputDelegate {

    var _parentItem;  // ссылка на MenuItem в родительском меню

    function initialize(parentItem) {
        Menu2InputDelegate.initialize();
        _parentItem = parentItem;
    }

    function onSelect(item) {
        var idx = item.getId();
        Application.Properties.setValue("weatherInterval", idx);
        _parentItem.setSubLabel(AppSettings.WEATHER_INTERVALS[idx] + " min");
        (Application.getApp() as F7_1App)._updateBackgroundImmediate();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

// ============================================================================
// WEEKEND COLOR PICKER
// ============================================================================
class WeekendColorPicker extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({ :title => "Weekend color" });

        var currentIdx = Application.Properties.getValue("weekendColor");
        if (currentIdx == null) { currentIdx = 0; }

        for (var i = 0; i < AppSettings.WEEKEND_COLOR_NAMES.size(); i++) {
            var label = (i == currentIdx) ? "[ " + AppSettings.WEEKEND_COLOR_NAMES[i] + " ]" : AppSettings.WEEKEND_COLOR_NAMES[i];
            Menu2.addItem(new WatchUi.MenuItem(label, null, i, {}));
        }

        Menu2.setFocus(currentIdx);
    }
}

class WeekendColorDelegate extends WatchUi.Menu2InputDelegate {

    var _parentItem;

    function initialize(parentItem) {
        Menu2InputDelegate.initialize();
        _parentItem = parentItem;
    }

    function onSelect(item) {
        var idx = item.getId();
        Application.Properties.setValue("weekendColor", idx);
        _parentItem.setSubLabel(AppSettings.WEEKEND_COLOR_NAMES[idx]);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

// ============================================================================
// BOTTOM BLOCK PICKER
// ============================================================================
class BottomBlockPicker extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({ :title => "Bottom block" });

        var currentIdx = Application.Properties.getValue("bottomBlock");
        if (currentIdx == null) { currentIdx = 0; }

        for (var i = 0; i < AppSettings.BLOCK_NAMES.size(); i++) {
            var label = (i == currentIdx) ? "[ " + AppSettings.BLOCK_NAMES[i] + " ]" : AppSettings.BLOCK_NAMES[i];
            Menu2.addItem(new WatchUi.MenuItem(label, null, i, {}));
        }

        Menu2.setFocus(currentIdx);
    }
}

class BottomBlockDelegate extends WatchUi.Menu2InputDelegate {

    var _parentItem;

    function initialize(parentItem) {
        Menu2InputDelegate.initialize();
        _parentItem = parentItem;
    }

    function onSelect(item) {
        var idx = item.getId();
        Application.Properties.setValue("bottomBlock", idx);
        _parentItem.setSubLabel(AppSettings.BLOCK_NAMES[idx]);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}