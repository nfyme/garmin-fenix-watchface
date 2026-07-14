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
        System.println("[OM-BG] ========== onTemporalEvent START ==========");

        var weatherSource = Application.Properties.getValue("weatherSource");
        if (weatherSource == null || weatherSource != 1) {
            System.println("[OM-BG] weatherSource=" + weatherSource + ", not Open-Meteo, skipping");
            Background.exit(null);
            return;
        }

        var locationSource = Application.Properties.getValue("locationSource");
        if (locationSource == null) { locationSource = 0; }
        System.println("[OM-BG] locationSource=" + locationSource + " (" + (locationSource == 0 ? "GPS" : "Garmin Weather") + ")");

        var lat = null;
        var lon = null;

        if (locationSource == 0) {
            // GPS: request last known position from the watch
            var posInfo = Position.getInfo();
            if (posInfo != null && posInfo.position != null) {
                var coords = posInfo.position.toDegrees();
                lat = coords[0].toDouble();
                lon = coords[1].toDouble();
                System.println("[OM-BG] GPS fix: lat=" + lat.format("%.5f") + " lon=" + lon.format("%.5f") + " accuracy=" + posInfo.accuracy);
                // Cache for next run in case GPS is unavailable
                Application.Storage.setValue("om_lat", lat);
                Application.Storage.setValue("om_lon", lon);
            } else {
                System.println("[OM-BG] GPS: no fix available, falling back to cached coords");
                lat = Application.Storage.getValue("om_lat");
                lon = Application.Storage.getValue("om_lon");
                if (lat != null) {
                    System.println("[OM-BG] Cached GPS coords: lat=" + lat + " lon=" + lon);
                } else {
                    System.println("[OM-BG] No cached GPS coords");
                }
            }
        } else {
            // Garmin Weather: FG stores these from Weather.getCurrentConditions()
            lat = Application.Storage.getValue("om_lat");
            lon = Application.Storage.getValue("om_lon");
            System.println("[OM-BG] Garmin Weather stored coords: lat=" + (lat != null ? lat.toString() : "null") + " lon=" + (lon != null ? lon.toString() : "null"));
        }

        if (lat == null || lon == null) {
            System.println("[OM-BG] ERROR: no coordinates available, aborting");
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

        System.println("[OM-BG] Request URL: " + url);
        System.println("[OM-BG] Params: latitude=" + latStr + " longitude=" + lonStr);
        System.println("[OM-BG] Params: hourly=temperature_2m,wind_speed_10m,wind_direction_10m,precipitation_probability,weathercode");
        System.println("[OM-BG] Params: timezone=auto forecast_days=2");

        var options = {
            :method  => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON }
        };

        Communications.makeWebRequest(url, params, options, method(:onResponse));
    }

    function onResponse(responseCode as Lang.Number, data as Lang.Dictionary or Null) as Void {
        System.println("[OM-BG] --------- onResponse ---------");
        System.println("[OM-BG] HTTP status: " + responseCode);

        if (responseCode != 200) {
            System.println("[OM-BG] ERROR: unexpected HTTP status " + responseCode);
            Background.exit(null);
            return;
        }
        if (data == null) {
            System.println("[OM-BG] ERROR: response data is null");
            Background.exit(null);
            return;
        }

        System.println("[OM-BG] Response keys: " + data.keys().toString());

        var hourly = data.get("hourly") as Lang.Dictionary?;
        if (hourly == null) {
            System.println("[OM-BG] ERROR: missing 'hourly' key in response");
            Background.exit(null);
            return;
        }

        var temps  = hourly.get("temperature_2m") as Lang.Array?;
        var times  = hourly.get("time")           as Lang.Array?;
        var codes  = hourly.get("weathercode")    as Lang.Array?;
        var winds  = hourly.get("wind_speed_10m") as Lang.Array?;
        var wdirs  = hourly.get("wind_direction_10m")          as Lang.Array?;
        var precip = hourly.get("precipitation_probability")   as Lang.Array?;
        var pressure = hourly.get("surface_pressure")          as Lang.Array?;

        var count = (temps != null) ? temps.size() : 0;
        System.println("[OM-BG] Hourly entries count: " + count);

        if (count > 0) {
            System.println("[OM-BG] Entry[0]: time=" + (times != null ? times[0] : "?")
                + " temp=" + (temps != null ? temps[0].toString() : "?")
                + " code=" + (codes != null ? codes[0].toString() : "?")
                + " wind=" + (winds != null ? winds[0].toString() : "?")
                + " wdir=" + (wdirs != null ? wdirs[0].toString() : "?")
                + " precip=" + (precip != null ? precip[0].toString() : "?"));
        }
        if (count > 12) {
            System.println("[OM-BG] Entry[12]: time=" + (times != null ? times[12] : "?")
                + " temp=" + (temps != null ? temps[12].toString() : "?"));
        }

        Application.Storage.setValue("om_temps",    temps);
        Application.Storage.setValue("om_times",    times);
        Application.Storage.setValue("om_codes",    codes);
        Application.Storage.setValue("om_winds",    winds);
        Application.Storage.setValue("om_wdir",     wdirs);
        Application.Storage.setValue("om_precip",   precip);
        Application.Storage.setValue("om_pressure", pressure);

        var nowSecs = Time.now().value();
        Application.Storage.setValue("om_updated", nowSecs);

        System.println("[OM-BG] Saved to Storage: om_temps, om_times, om_codes, om_winds, om_wdir, om_precip");
        System.println("[OM-BG] om_updated=" + nowSecs + " (unix timestamp)");
        System.println("[OM-BG] ========== onTemporalEvent END ==========");

        Background.exit(true);
    }
}
