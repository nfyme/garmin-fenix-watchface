using Toybox.Application;
using Toybox.WatchUi;
using Toybox.Application.Storage;

class F7_1App extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        return [ new F7_1View() ];
    }

    // Вызывается при "Настроить циферблат" → UP → Customize
    function getSettingsView() {
        return [ new SettingsMenuView(), new SettingsMenuDelegate() ];
    }
}
