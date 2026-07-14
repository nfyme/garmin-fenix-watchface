using Toybox.Background;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.Position;
using Toybox.Application;
using Toybox.System;
using Toybox.Time;

(:background)
class OpenMeteoBackground extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() {
        var weatherSource = Application.Properties.getValue("weatherSource");
        if (weatherSource == null || weatherSource != 1) {
            Background.exit(null);
            return;
        }

        var locationSource = Application.Properties.getValue("locationSource");
        if (locationSource == null) { locationSource = 0; }

        var lat = null;
        var lon = null;

        if (locationSource == 0) {
            // GPS: request last known position from the watch
            var posInfo = Position.getInfo();
            if (posInfo != null && posInfo.position != null) {
                var coords = posInfo.position.toDegrees();
                lat = coords[0].toDouble();
                lon = coords[1].toDouble();
                // Cache for next run in case GPS is unavailable
                Application.Storage.setValue("om_lat", lat);
                Application.Storage.setValue("om_lon", lon);
            } else {
                lat = Application.Storage.getValue("om_lat");
                lon = Application.Storage.getValue("om_lon");
            }
        } else {
            // Garmin Weather: FG stores these from Weather.getCurrentConditions()
            lat = Application.Storage.getValue("om_lat");
            lon = Application.Storage.getValue("om_lon");
        }

        if (lat == null || lon == null) {
            Background.exit(null);
            return;
        }

        var latStr = lat.toDouble().format("%.5f");
        var lonStr = lon.toDouble().format("%.5f");

        var url = "https://api.open-meteo.com/v1/forecast";
        var params = {
            "latitude"        => latStr,
            "longitude"       => lonStr,
            "hourly"          => "temperature_2m,wind_speed_10m,wind_direction_10m,precipitation_probability,weathercode,surface_pressure",
            "timezone"        => "auto",
            "forecast_days"   => "3",
            "wind_speed_unit" => "ms"
        };

        var options = {
            :method  => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON }
        };

        Communications.makeWebRequest(url, params, options, method(:onResponse));
    }

    function onResponse(responseCode as Lang.Number, data as Lang.Dictionary or Null) as Void {
        if (responseCode != 200) {
            Background.exit(null);
            return;
        }
        if (data == null) {
            Background.exit(null);
            return;
        }

        var hourly = data.get("hourly") as Lang.Dictionary?;
        if (hourly == null) {
            Background.exit(null);
            return;
        }

        var temps    = hourly.get("temperature_2m")            as Lang.Array?;
        var times    = hourly.get("time")                      as Lang.Array?;
        var codes    = hourly.get("weathercode")                as Lang.Array?;
        var winds    = hourly.get("wind_speed_10m")             as Lang.Array?;
        var wdirs    = hourly.get("wind_direction_10m")         as Lang.Array?;
        var precip   = hourly.get("precipitation_probability")  as Lang.Array?;
        var pressure = hourly.get("surface_pressure")           as Lang.Array?;

        Application.Storage.setValue("om_temps",    temps);
        Application.Storage.setValue("om_times",    times);
        Application.Storage.setValue("om_codes",    codes);
        Application.Storage.setValue("om_winds",    winds);
        Application.Storage.setValue("om_wdir",     wdirs);
        Application.Storage.setValue("om_precip",   precip);
        Application.Storage.setValue("om_pressure", pressure);

        Application.Storage.setValue("om_updated", Time.now().value());

        Background.exit(true);
    }
}
