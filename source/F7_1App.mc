using Toybox.Application;
using Toybox.WatchUi;

class F7_1App extends Application.AppBase {

    var _view;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        _view = new F7_1View();
        return [ _view ];
    }

    function getSettingsView() {
        return [ new SettingsMenuView(), new SettingsMenuDelegate() ];
    }

    function onSettingsChanged() {
        if (_view != null) {
            _view.loadSettings();
        }
        WatchUi.requestUpdate();
    }
}