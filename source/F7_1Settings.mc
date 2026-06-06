using Toybox.WatchUi;
using Toybox.Application.Storage;
using Toybox.Graphics;

// ============================================================================
// SETTINGS STORAGE
// ============================================================================
class AppSettings {

    static var WEATHER_INTERVALS = [5, 10, 15, 30, 60];

    static var WEEKEND_COLORS = [
        0xAA0000,
        0xFF5500,
        0x00AA00,
        0x0055FF,
        Graphics.COLOR_LT_GRAY
    ];

    static var WEEKEND_COLOR_NAMES = ["Red", "Orange", "Green", "Blue", "Gray"];
    static var BLOCK_NAMES = ["Calendar", "Sport"];

    static function getWeatherInterval() {
        var idx = Storage.getValue("weatherInterval");
        if (idx == null || idx < 0 || idx >= WEATHER_INTERVALS.size()) { idx = 2; }
        return WEATHER_INTERVALS[idx];
    }

    static function getWeekendColor() {
        var idx = Storage.getValue("weekendColor");
        if (idx == null || idx < 0 || idx >= WEEKEND_COLORS.size()) { idx = 0; }
        return WEEKEND_COLORS[idx];
    }

    static function getBottomBlock() {
        var val = Storage.getValue("bottomBlock");
        if (val == null) { val = 0; }
        return val;
    }

    static function getPrecipRing() {
        var val = Storage.getValue("precipRing");
        if (val == null) { val = true; }
        return val;
    }

    static function getPrecipForecast() {
        var val = Storage.getValue("precipForecast");
        if (val == null) { val = true; }
        return val;
    }

    static function getWeatherDisplay() {
        var val = Storage.getValue("weatherDisplay");
        if (val == null) { val = true; }
        return val;
    }

    static function getHeartRate() {
        var val = Storage.getValue("heartRate");
        if (val == null) { val = true; }
        return val;
    }
}

// ============================================================================
// MAIN SETTINGS MENU
// ============================================================================
class SettingsMenuView extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({ :title => "Dark Watch" });

        var wIdx = Storage.getValue("weatherInterval");
        if (wIdx == null) { wIdx = 2; }

        var cIdx = Storage.getValue("weekendColor");
        if (cIdx == null) { cIdx = 0; }

        var bIdx = Storage.getValue("bottomBlock");
        if (bIdx == null) { bIdx = 0; }

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

        if (id == :weatherInterval) {
            WatchUi.pushView(
                new WeatherIntervalPicker(),
                new WeatherIntervalDelegate(item),  // передаём item
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
            Storage.setValue("precipRing", (item as WatchUi.ToggleMenuItem).isEnabled());
        }
        else if (id == :precipForecast) {
            Storage.setValue("precipForecast", (item as WatchUi.ToggleMenuItem).isEnabled());
        }
        else if (id == :weatherDisplay) {
            Storage.setValue("weatherDisplay", (item as WatchUi.ToggleMenuItem).isEnabled());
        }
        else if (id == :heartRate) {
            Storage.setValue("heartRate", (item as WatchUi.ToggleMenuItem).isEnabled());
        }
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

        var currentIdx = Storage.getValue("weatherInterval");
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
        Storage.setValue("weatherInterval", idx);
        // Обновляем subLabel прямо в родительском меню — оно живёт в стеке
        _parentItem.setSubLabel(AppSettings.WEATHER_INTERVALS[idx] + " min");
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

        var currentIdx = Storage.getValue("weekendColor");
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
        Storage.setValue("weekendColor", idx);
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

        var currentIdx = Storage.getValue("bottomBlock");
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
        Storage.setValue("bottomBlock", idx);
        _parentItem.setSubLabel(AppSettings.BLOCK_NAMES[idx]);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}