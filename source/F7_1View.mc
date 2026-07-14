using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.System;
using Toybox.Position;
using Toybox.Math;
using Toybox.Weather;
using Toybox.ActivityMonitor;
using Toybox.Activity;
using Toybox.Application;
using Toybox.Lang;

class F7_1View extends WatchUi.WatchFace {

    // Кэш ежедневных вычислений
    var riseStr     = "--:--";
    var setStr      = "--:--";
    var moonPhase   = 0.0;
    var lastCalcDay = -1;

    // Буфер луны (CIQ 4.x: createBufferedBitmap → Reference, да, не сам bitmap —
    // словил на этом NPE один раз, теперь помню навсегда)
    var moonBuffer  = null;
    var lastMoonDay = -1;
    // MOON_R теперь вычисляется динамически в ensureMoonBuffer

    // Кэш погоды
    var cachedWeatherBlocks = null;
    var cachedPrecipData    = null;  // полный форecast (сколько отдал API), каждый элемент содержит "time" (unix sec)
    var lastWeatherMin      = -1;
    var omUpdatedAt         = 0;    // unix timestamp последнего успешного OM-запроса
    var cachedPressure      = null; // текущее давление, hPa (null пока не получено)

    // Настройки (читаются при старте и после изменения)
    var settingWeatherInterval = 15;
    var settingWeekendColor    = 0xAA0000;
    var settingBottomBlock     = 0;   // 0=calendar, 1=sport

    const COLORS_RAIN   = 0x0000AA;
    const COLORS_SNOW   = Graphics.COLOR_WHITE;
    const COLORS_MIX    = 0x4488FF;
    const COLORS_DANGER = 0xFF5500;

    // Верхний потолок для кэша forecast'а (в часах). Берём столько, сколько
    // реально отдаёт API (не завязываемся на фиксированное число слотов), но
    // не более этого предела — на случай, если API однажды начнёт отдавать
    // существенно больше, чтобы не раздувать память бесконечно.
    // Часы на watch — не заметят, а вот память там жмётся будь здоров.
    const MAX_FORECAST_HOURS = 72;

    function initialize() {
        WatchFace.initialize();
    }

    function loadSettings() {
        settingWeatherInterval = AppSettings.getWeatherInterval();
        settingWeekendColor    = AppSettings.getWeekendColor();
        settingBottomBlock     = AppSettings.getBottomBlock();
    }

    function onShow() {
        loadSettings();
        lastCalcDay    = -1;
        lastWeatherMin = -1;  // форсируем попытку обновления, но кэш НЕ обнуляем —
                              // старые данные остаются на экране, пока не придут свежие.
                              // Обнулишь тут кэш — экран мигнёт пустотой, дизайнер не простит.
        lastMoonDay    = -1;
        moonBuffer     = null;
    }

    // -------------------------------------------------------------------------
    // Ежедневные вычисления
    // -------------------------------------------------------------------------
    function recalcDaily(info) {
        calculateSunTimes();
        moonPhase   = getMoonPhase(info.year, info.month, info.day);
        lastCalcDay = info.day;
        lastMoonDay = -1;
        moonBuffer  = null; // размер радиуса мог измениться
    }

    // Стандартная астроформула восхода/заката (NOAA). Магические числа
    // ниже — не от балды, это уравнение времени и наклон эклиптики,
    // трогать только если реально шаришь в астрономии.
    function calculateSunTimes() {
        riseStr = "--:--";
        setStr  = "--:--";
        var posInfo = Position.getInfo();
        if (posInfo == null || posInfo.position == null) { return; }
        var latLon = posInfo.position.toDegrees();
        var lat    = latLon[0].toFloat() * Math.PI / 180.0;
        var lonDeg = latLon[1].toFloat();
        var now = Time.now();
        var jd  = now.value().toFloat() / 86400.0 + 2440587.5;
        var n   = jd - 2451545.0;
        var L = normDeg(280.460 + 0.9856474 * n);
        var g = normDeg(357.528 + 0.9856003 * n);
        var gRad   = g * Math.PI / 180.0;
        var lambda = normDeg(L + 1.915 * Math.sin(gRad) + 0.020 * Math.sin(2.0 * gRad));
        var epsilon = 23.439 - 0.0000004 * n;
        var epsRad  = epsilon * Math.PI / 180.0;
        var lamRad  = lambda  * Math.PI / 180.0;
        var decl    = Math.asin(Math.sin(epsRad) * Math.sin(lamRad));
        var y  = Math.tan(epsRad / 2.0); y = y * y;
        var e  = 0.016708634;
        var eq = y * Math.sin(2.0 * lamRad)
               - 2.0 * e * Math.sin(gRad)
               + 4.0 * e * y * Math.sin(gRad) * Math.cos(2.0 * lamRad)
               - 0.5 * y * y * Math.sin(4.0 * lamRad)
               - 1.25 * e * e * Math.sin(2.0 * gRad);
        eq = eq * 180.0 / Math.PI * 4.0;
        var solarNoon = 12.0 - lonDeg / 15.0 - eq / 60.0;
        var zenithRad = 90.833 * Math.PI / 180.0;
        var cosH = (Math.cos(zenithRad) - Math.sin(lat) * Math.sin(decl))
                 / (Math.cos(lat) * Math.cos(decl));
        if (cosH < -1.0) { riseStr = "polar";  setStr = "polar";  return; }
        if (cosH >  1.0) { riseStr = "no sun"; setStr = "no sun"; return; }
        var Hhours   = Math.acos(cosH) * 12.0 / Math.PI;
        var tzOffset = System.getClockTime().timeZoneOffset.toFloat() / 3600.0;
        var sunrise  = normHours(solarNoon - Hhours + tzOffset);
        var sunset   = normHours(solarNoon + Hhours + tzOffset);
        var rH = sunrise.toNumber(); var rM = ((sunrise - rH) * 60.0).toNumber();
        var sH = sunset.toNumber();  var sM = ((sunset  - sH) * 60.0).toNumber();
        riseStr = rH.format("%02d") + ":" + rM.format("%02d");
        setStr  = sH.format("%02d") + ":" + sM.format("%02d");
    }

    // Юлианская дата: a/y/m/jd — целочисленное деление (Number / Number в Monkey C).
    // Забудешь — фаза луны едет на пару дней, ищи потом баг неделю.
    function getMoonPhase(year, month, day) {
        var a  = (14 - month) / 12;
        var y  = year + 4800 - a;
        var m  = month + 12 * a - 3;
        var jd = (day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045).toFloat();
        var synodic = 29.53058867;
        var diff    = jd - 2451550.1;
        var cycles  = (diff / synodic).toNumber().toFloat();
        var days    = diff - cycles * synodic;
        if (days < 0.0) { days = days + synodic; }
        return days / synodic;
    }

    // -------------------------------------------------------------------------
    // Луна в BufferedBitmap (раз в день)
    // moonR передаётся снаружи и зависит от размера экрана
    // -------------------------------------------------------------------------
    function ensureMoonBuffer(day, moonR) {
        if (lastMoonDay == day && moonBuffer != null) { return; }

        var size = moonR * 2 + 4;

        if (!(Graphics has :createBufferedBitmap)) {
            moonBuffer = null;
            return;
        }

        moonBuffer = Graphics.createBufferedBitmap({
            :width  => size,
            :height => size
        });

        var bdc = moonBuffer.get().getDc();
        bdc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_TRANSPARENT);
        bdc.clear();

        var cx = size / 2;
        var cy = size / 2;
        var r  = moonR;
        var phase = moonPhase;
        if (phase >= 1.0) { phase = 0.0; }

        // Освещённая часть
        if (phase > 0.03 && phase < 0.97) {
            for (var dy = -r + 1; dy < r; dy++) {
                var dxF = Math.sqrt((r * r - dy * dy).toFloat());
                var dx  = dxF.toNumber();
                if (dx == 0) { continue; }

                var xL = cx - dx;
                var xR = cx + dx;

                bdc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

                if (phase <= 0.5) {
                    // Растущая: серп справа
                    var k = 1.0 - phase * 4.0;
                    var termX = cx + (dxF * k).toNumber();
                    if (termX < xR) { bdc.drawLine(termX, cy + dy, xR, cy + dy); }
                } else {
                    // Убывающая: серп слева
                    var k = phase * 4.0 - 3.0;
                    var termX = cx - (dxF * k).toNumber();
                    if (termX > xL) { bdc.drawLine(xL, cy + dy, termX, cy + dy); }
                }
            }
        }

        // Тонкое кольцо поверх
        bdc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        bdc.setPenWidth(1);
        bdc.drawCircle(cx, cy, r);

        lastMoonDay = day;
    }

    function getDaysToNextPhase() {
        var synodic = 29.53058867;
        var daysInCycle = moonPhase * synodic;

        var toFull = 14.765 - daysInCycle;
        if (toFull < 0) { toFull = toFull + synodic; }

        var toNew = synodic - daysInCycle;
        if (toNew >= synodic) { toNew = 0.0; }

        if (toFull <= toNew) {
            return [toFull.toNumber(), true];  // до полнолуния
        } else {
            return [toNew.toNumber(), false];  // до новолуния
        }
    }

    function blitMoon(dc, cx, cy, moonR) {
        if (moonBuffer == null) { return; }
        var size = moonR * 2 + 4;
        dc.drawBitmap(cx - size / 2, cy - size / 2, moonBuffer.get());
    }

    // -------------------------------------------------------------------------
    // WMO код (Open-Meteo) → Garmin condition code
    // -------------------------------------------------------------------------
    function wmoToGarminCond(wmo as Lang.Number) as Lang.Number {
        if (wmo == 95 || wmo == 96 || wmo == 99) { return 12; }  // гроза
        if (wmo == 65 || wmo == 82)               { return 25; }  // сильный дождь
        if (wmo == 61 || wmo == 63 || wmo == 80 || wmo == 81) { return 3; }  // дождь
        if (wmo == 51 || wmo == 53 || wmo == 55) { return 14; }  // морось
        if (wmo == 56 || wmo == 57 || wmo == 66 || wmo == 67) { return 18; }  // ледяной дождь
        if (wmo == 75 || wmo == 77 || wmo == 86) { return 17; }  // сильный снег (CONDITION_HEAVY_SNOW)
        if (wmo == 71 || wmo == 73 || wmo == 85) { return 4; }   // снег
        if (wmo == 45 || wmo == 48)              { return 8; }   // туман (CONDITION_FOG)
        return 0;
    }

    // -------------------------------------------------------------------------
    // Единая классификация Garmin CONDITION_* кода погоды.
    // Один источник правды для кольца осадков и текстовых блоков — оба места
    // рисуют по type/intensity/isDanger, вместо трёх рассинхронизированных
    // списков кодов, как было раньше. Ну наконец-то, а то задолбался в трёх
    // местах один и тот же код погоды на глаз сверять.
    // -------------------------------------------------------------------------
    const COND_NONE = 0;
    const COND_RAIN = 1;
    const COND_SNOW = 2;
    const COND_MIX  = 3;

    const INTENSITY_LIGHT  = 0;
    const INTENSITY_NORMAL = 1;
    const INTENSITY_HEAVY  = 2;

    function classifyCondition(cond) {
        // isDanger: экстремальные единичные явления — гроза, торнадо, ураган,
        // тропический шторм, град, гололёд, sandstorm/volcanic ash.
        // Осознанно не включает WINDY (5) — "просто ветрено" не осадки и не
        // экстремальное явление само по себе.
        var isDanger = (cond==6 || cond==12 || cond==28          // гроза
                     || cond==32 || cond==41 || cond==42          // торнадо/ураган/тропич.шторм
                     || cond==10 || cond==34                      // град/гололёд
                     || cond==36 || cond==37 || cond==38);        // squall/sandstorm/volcanic ash

        // Дождь: морось, ливни, обычный/сильный дождь
        if (cond==31 || cond==24 || cond==14) {
            return { "type" => COND_RAIN, "intensity" => INTENSITY_LIGHT,  "isDanger" => isDanger };
        }
        if (cond==3 || cond==11 || cond==13 || cond==45 || cond==27) {
            return { "type" => COND_RAIN, "intensity" => INTENSITY_NORMAL, "isDanger" => isDanger };
        }
        if (cond==15 || cond==25 || cond==26) {
            return { "type" => COND_RAIN, "intensity" => INTENSITY_HEAVY,  "isDanger" => isDanger };
        }

        // Снег
        if (cond==16 || cond==43 || cond==48) {
            return { "type" => COND_SNOW, "intensity" => INTENSITY_LIGHT,  "isDanger" => isDanger };
        }
        if (cond==4 || cond==46) {
            return { "type" => COND_SNOW, "intensity" => INTENSITY_NORMAL, "isDanger" => isDanger };
        }
        if (cond==17) {
            return { "type" => COND_SNOW, "intensity" => INTENSITY_HEAVY,  "isDanger" => isDanger };
        }

        // Микс (дождь+снег, ледяной дождь, мокрый снег)
        if (cond==18 || cond==44 || cond==47) {
            return { "type" => COND_MIX, "intensity" => INTENSITY_LIGHT,  "isDanger" => isDanger };
        }
        if (cond==21 || cond==50 || cond==7 || cond==49 || cond==51) {
            return { "type" => COND_MIX, "intensity" => INTENSITY_NORMAL, "isDanger" => isDanger };
        }
        if (cond==19) {
            return { "type" => COND_MIX, "intensity" => INTENSITY_HEAVY,  "isDanger" => isDanger };
        }

        // Явления без выраженных осадков (гроза без указанной интенсивности
        // осадков, торнадо/ураган/град и т.п.) — если danger, всё равно нужен
        // тип для второго кольца/линии; используем MIX как нейтральный визуал.
        if (isDanger) {
            return { "type" => COND_MIX, "intensity" => INTENSITY_NORMAL, "isDanger" => true };
        }

        return { "type" => COND_NONE, "intensity" => INTENSITY_LIGHT, "isDanger" => false };
    }

    function condTypeColor(type) {
        if (type == COND_RAIN) { return COLORS_RAIN; }
        if (type == COND_SNOW) { return COLORS_SNOW; }
        if (type == COND_MIX)  { return COLORS_MIX; }
        return Graphics.COLOR_TRANSPARENT;
    }

    const MAX_PRECIP_THICKNESS = 6; // должно совпадать с макс. значением из condIntensityThickness

    function condIntensityThickness(intensity) {
        if (intensity == INTENSITY_HEAVY)  { return 6; }
        if (intensity == INTENSITY_NORMAL) { return 4; }
        return 2;
    }

    // -------------------------------------------------------------------------
    // Обновление кэша погоды из Open-Meteo Storage
    // -------------------------------------------------------------------------
    function refreshWeatherCacheOpenMeteo(nowMin) {
        var temps    = Application.Storage.getValue("om_temps")    as Lang.Array?;
        var times    = Application.Storage.getValue("om_times")    as Lang.Array?;
        var codes    = Application.Storage.getValue("om_codes")    as Lang.Array?;
        var winds    = Application.Storage.getValue("om_winds")    as Lang.Array?;
        var wdirs    = Application.Storage.getValue("om_wdir")     as Lang.Array?;
        var precip   = Application.Storage.getValue("om_precip")   as Lang.Array?;
        var pressure = Application.Storage.getValue("om_pressure") as Lang.Array?;

        if (temps == null || temps.size() == 0 || times == null) {
            return;
        }

        // Находим индекс текущего часа по массиву времён "YYYY-MM-DDTHH:00"
        // Это надёжнее чем nowInfo.hour — работает корректно даже если данные
        // получены несколько часов/дней назад
        var nowInfo = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var curStr  = nowInfo.year.format("%04d") + "-"
                    + nowInfo.month.format("%02d") + "-"
                    + nowInfo.day.format("%02d") + "T"
                    + nowInfo.hour.format("%02d") + ":00";

        var curIdx = -1;
        for (var i = 0; i < times.size(); i++) {
            if ((times[i] as Lang.String).equals(curStr)) {
                curIdx = i;
                break;
            }
        }

        if (curIdx < 0) {
            // Данные устарели (все часы прошли), кэш не обновляем
            return;
        }

        // 3 блока погоды: сейчас, +3ч, +6ч
        var newBlocks = new [3];
        var offsets = [0, 3, 6];
        for (var i = 0; i < 3; i++) {
            var idx = curIdx + offsets[i];
            if (idx < temps.size()) {
                var windMs = (winds != null && idx < winds.size()) ? (winds[idx] as Lang.Float) : null;
                newBlocks[i] = {
                    "temp"   => temps[idx],
                    "wind"   => windMs,
                    "wdir"   => (wdirs  != null && idx < wdirs.size())  ? (wdirs[idx]  as Lang.Number) : null,
                    "precip" => (precip != null && idx < precip.size()) ? (precip[idx] as Lang.Number) : null,
                    "cond"   => (codes  != null && idx < codes.size())  ? wmoToGarminCond(codes[idx] as Lang.Number) : 0
                };
            }
        }
        cachedWeatherBlocks = newBlocks;

        // Давление — только текущий час, Open-Meteo уже отдаёт hPa напрямую
        if (pressure != null && curIdx < pressure.size()) {
            cachedPressure = pressure[curIdx];
        }

        // Кольцо осадков: держим ВЕСЬ форecast от текущего часа до конца массива
        // (сколько Open-Meteo отдал — forecast_days=3 даёт до 72ч), а не только 12.
        // Каждый слот идёт ровно на 1 час дальше curIdx, поэтому abs.время
        // считаем как смещение от "сейчас", не парся строку times[idx].
        var nowSecs = Time.now().value();
        var total   = temps.size() - curIdx;
        if (total > MAX_FORECAST_HOURS) { total = MAX_FORECAST_HOURS; }
        var newPrecip = new [total];
        for (var i = 0; i < total; i++) {
            var idx = curIdx + i;
            newPrecip[i] = {
                "time"         => nowSecs + i * 3600,
                "condition"    => (codes  != null && idx < codes.size())  ? wmoToGarminCond(codes[idx] as Lang.Number) : 0,
                "precipChance" => (precip != null && idx < precip.size()) ? (precip[idx] as Lang.Number) : 0
            };
        }
        cachedPrecipData = newPrecip;

        var updated = Application.Storage.getValue("om_updated");
        omUpdatedAt = (updated != null) ? updated : 0;

        lastWeatherMin = nowMin;
    }

    // -------------------------------------------------------------------------
    // Демо-режим: захардкоженный набор данных, покрывающий все варианты
    // type/intensity/isDanger — для тестирования отрисовки и скриншотов
    // без реальных запросов к Garmin Weather / Open-Meteo.
    // -------------------------------------------------------------------------
    // 12 часовых слотов кольца — все Garmin CONDITION_* коды подобраны так,
    // чтобы classifyCondition() прошла через каждую комбинацию type×intensity,
    // плюс несколько isDanger случаев (гроза, торнадо, град).
    const DEMO_RING_CONDITIONS = [
        14, // rain light
        3,  // rain normal
        15, // rain heavy
        16, // snow light
        4,  // snow normal
        17, // snow heavy
        18, // mix light
        21, // mix normal
        19, // mix heavy
        6,  // thunder (danger)
        32, // tornado (danger)
        10  // hail (danger)
    ];
    const DEMO_RING_PRECIP_CHANCES = [0, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100];

    // 3 текстовых блока: показательные разные случаи (лёгкий дождь, гроза/danger, снег)
    const DEMO_BLOCK_CONDITIONS     = [14, 6, 4];
    const DEMO_BLOCK_TEMPS          = [12, 18, -3];
    const DEMO_BLOCK_WINDS          = [3.5, 9.0, 5.0];
    const DEMO_BLOCK_WDIRS          = [45, 180, 270];
    const DEMO_BLOCK_PRECIP_CHANCES = [40, 80, 60];
    const DEMO_PRESSURE             = 995; // hPa, ниже нормы — видно заполнение влево от центра

    function refreshWeatherCacheDemo(nowMin) {
        var newBlocks = new [3];
        for (var i = 0; i < 3; i++) {
            newBlocks[i] = {
                "temp"   => DEMO_BLOCK_TEMPS[i],
                "wind"   => DEMO_BLOCK_WINDS[i],
                "wdir"   => DEMO_BLOCK_WDIRS[i],
                "precip" => DEMO_BLOCK_PRECIP_CHANCES[i],
                "cond"   => DEMO_BLOCK_CONDITIONS[i]
            };
        }
        cachedWeatherBlocks = newBlocks;
        cachedPressure = DEMO_PRESSURE;

        var nowSecs = Time.now().value();
        var newPrecip = new [ DEMO_RING_CONDITIONS.size() ];
        for (var i = 0; i < DEMO_RING_CONDITIONS.size(); i++) {
            newPrecip[i] = {
                "time"         => nowSecs + i * 3600,
                "condition"    => DEMO_RING_CONDITIONS[i],
                "precipChance" => DEMO_RING_PRECIP_CHANCES[i]
            };
        }
        cachedPrecipData = newPrecip;

        omUpdatedAt    = nowSecs;
        lastWeatherMin = nowMin;
    }

    // -------------------------------------------------------------------------
    // Обновление кэша погоды (Garmin)
    // -------------------------------------------------------------------------
    // Кэш хранит ВЕСЬ форecast, который в этот раз отдало API (не ограничиваем
    // фиксированным числом слотов — сколько дали, столько и держим). Если API
    // сейчас ничего не отдаёт (null), старый кэш не трогаем — он и так уже
    // содержит максимум того, что было получено ранее, и остаётся доступным
    // для отрисовки, пока не придут свежие данные.
    function refreshWeatherCache(nowMin) {
        var cur    = Weather.getCurrentConditions();
        var hourly = Weather.getHourlyForecast();

        if (cur != null || hourly != null) {
            var newBlocks = new [3];
            if (cur != null) {
                newBlocks[0] = { "temp" => cur.temperature, "wind" => cur.windSpeed,
                                 "wdir" => cur.windBearing, "precip" => cur.precipitationChance,
                                 "cond" => cur.condition };
                // Garmin отдаёт давление в Pa, переводим в hPa для отображения
                if (cur.pressure != null) { cachedPressure = cur.pressure / 100.0; }
            } else if (cachedWeatherBlocks != null) {
                newBlocks[0] = cachedWeatherBlocks[0];
            }

            if (hourly != null) {
                var now = Time.now().value(); var found3 = false; var found6 = false;
                for (var i = 0; i < hourly.size(); i++) {
                    var h = hourly[i];
                    if (h == null || h.forecastTime == null) { continue; }
                    var diff = (h.forecastTime.value() - now) / 3600;
                    if (!found3 && diff >= 2 && diff <= 4) {
                        newBlocks[1] = { "temp" => h.temperature, "wind" => h.windSpeed,
                                         "wdir" => h.windBearing, "precip" => h.precipitationChance,
                                         "cond" => h.condition };
                        found3 = true;
                    }
                    if (!found6 && diff >= 5 && diff <= 7) {
                        newBlocks[2] = { "temp" => h.temperature, "wind" => h.windSpeed,
                                         "wdir" => h.windBearing, "precip" => h.precipitationChance,
                                         "cond" => h.condition };
                        found6 = true;
                    }
                }
            } else if (cachedWeatherBlocks != null) {
                newBlocks[1] = cachedWeatherBlocks[1];
                newBlocks[2] = cachedWeatherBlocks[2];
            }
            cachedWeatherBlocks = newBlocks;

            // Полный список: текущие условия + весь hourly forecast, сколько API
            // отдал (не ограничиваемся фиксированным числом слотов), но не
            // больше MAX_FORECAST_HOURS на случай, если API станет отдавать
            // существенно больше часов вперёд.
            var hourlyCount = hourly != null ? hourly.size() : 0;
            if (hourlyCount > MAX_FORECAST_HOURS) { hourlyCount = MAX_FORECAST_HOURS; }
            var newPrecip = new [ hourlyCount + (cur != null ? 1 : 0) ];
            var idx = 0;
            if (cur != null) {
                newPrecip[idx] = { "time"         => Time.now().value(),
                                    "condition"    => (cur.condition != null)           ? cur.condition           : 0,
                                    "precipChance" => (cur.precipitationChance != null) ? cur.precipitationChance : 0 };
                idx++;
            }
            if (hourly != null) {
                for (var i = 0; i < hourlyCount; i++) {
                    var hh = hourly[i];
                    if (hh == null || hh.forecastTime == null) { continue; }
                    newPrecip[idx] = { "time"         => hh.forecastTime.value(),
                                        "condition"    => (hh.condition != null)           ? hh.condition           : 0,
                                        "precipChance" => (hh.precipitationChance != null) ? hh.precipitationChance : 0 };
                    idx++;
                }
            }
            cachedPrecipData = newPrecip;
            lastWeatherMin = nowMin;
        }
        // Оба null: API пока ничего не отдал — оставляем весь предыдущий кэш
        // как есть и попробуем снова на следующем тике (onUpdate вызовет
        // refreshWeatherCache опять, т.к. lastWeatherMin не обновлён).
    }

    // -------------------------------------------------------------------------
    // Иконки восход / закат
    // -------------------------------------------------------------------------
    function drawSunrise(dc, x, y, size) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x, y + size, x + size, y);
        dc.drawLine(x + size, y, x + size - size/2, y);
        dc.drawLine(x + size, y, x + size, y + size/2);
    }

    function drawSunset(dc, x, y, size) {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x, y, x + size, y + size);
        dc.drawLine(x + size, y + size, x + size - size/2, y + size);
        dc.drawLine(x + size, y + size, x + size, y + size - size/2);
    }

    // -------------------------------------------------------------------------
    // Календарь
    // -------------------------------------------------------------------------
    function drawCalendar(dc, startY) {
        var now  = Time.now();
        var info = Gregorian.info(now, Time.FORMAT_SHORT);
        var w    = dc.getWidth();
        var h    = dc.getHeight();
        var today       = info.day;
        var firstDow    = getFirstDayOfMonth(info.year, info.month);
        var daysInMonth = getDaysInMonth(info.year, info.month);
        var firstDowMon = (firstDow + 6) % 7;
        var todayDow    = (info.day_of_week - 2 + 7) % 7;
        var days = ["Mo","Tu","We","Th","Fr","Sa","Su"];

        var cellW = w / 10.5;
        if (cellW > 40) { cellW = 40; }
        var offsetX = (w - cellW * 7) / 2;

        // Доступная высота для календаря: от startY до нижней метки BT (10% снизу)
        var availH = h - (h * 10 / 100) - startY;
        // 7 строк: 1 заголовок + 6 недель. rowH — высота одной строки.
        var rowH = availH / 6.5;

        var underlineLen = (w * 7 / 100);

        for (var i = 0; i < 7; i++) {
            dc.setColor((i >= 5) ? settingWeekendColor : Graphics.COLOR_LT_GRAY,
                        Graphics.COLOR_TRANSPARENT);
            var textX = offsetX + cellW * i + cellW / 2;
            dc.drawText(textX, startY, Graphics.FONT_XTINY, days[i], Graphics.TEXT_JUSTIFY_CENTER);
            if (i == todayDow) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(textX - underlineLen/2, startY + rowH+2,
                            textX + underlineLen/2, startY + rowH+2);
                dc.drawLine(textX - underlineLen/2, startY + rowH+1,
                            textX + underlineLen/2, startY + rowH+1);
            }
        }

        var col = firstDowMon; var row = 1;
        for (var d = 1; d <= daysInMonth; d++) {
            var x = offsetX + col * cellW + cellW / 2;
            var y = startY + row * rowH;
            if (d == today) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawRectangle(offsetX + col * cellW + 2, y + 1, cellW - 2, rowH+2 );
            }
            dc.setColor((col >= 5) ? settingWeekendColor : Graphics.COLOR_WHITE,
                        Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, Graphics.FONT_XTINY, d.format("%d"), Graphics.TEXT_JUSTIFY_CENTER);
            col++;
            if (col > 6) { col = 0; row++; }
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
    }

    // -------------------------------------------------------------------------
    // Общий фон бара (заполняемая полоска): -1 = не рисовать (прозрачный),
    // -2 = только контур без заливки, иначе обычная заливка цветом.
    // -------------------------------------------------------------------------
    function drawBarBg(dc, barX, barY, barW, barH) {
        var bgColor = AppSettings.getBarBgColor();
        if (bgColor == -1) { return; }
        if (bgColor == -2) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(barX, barY, barW, barH, barH / 2);
            return;
        }
        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(barX, barY, barW, barH, barH / 2);
    }

    // -------------------------------------------------------------------------
    // Прогресс-бар шагов. Координаты полностью задаются вызывающим кодом:
    // y — вертикальный центр бара, s/e — левая/правая граница по X (по
    // умолчанию 0 и ширина экрана). Никакой автоматической геометрии внутри.
    // -------------------------------------------------------------------------
    const DEMO_STEPS      = 7000;
    const DEMO_STEPS_GOAL = 10000; // 70%, для скриншотов/теста в демо-режиме

    function drawStepsBar(dc, y, s, e) {
        var steps;
        var stepsGoal;
        if (AppSettings.getWeatherDemoMode()) {
            steps     = DEMO_STEPS;
            stepsGoal = DEMO_STEPS_GOAL;
        } else {
            var amInfo = ActivityMonitor.getInfo();
            if (amInfo == null) { return; }
            steps     = amInfo.steps;
            stepsGoal = amInfo.stepGoal;
        }
        if (steps == null || stepsGoal == null || stepsGoal <= 0) { return; }

        var h = dc.getHeight();

        if (s == null) { s = 0; }
        if (e == null) { e = dc.getWidth(); }

        var barH = (h * 2 / 100);
        if (barH < 3) { barH = 3; }
        var barY = y - barH / 2;
        var barX = s;
        var barW = e - s;

        var pct = steps.toFloat() / stepsGoal.toFloat();
        if (pct > 1.0) { pct = 1.0; }
        var fillW = (barW * pct).toNumber();

        drawBarBg(dc, barX, barY, barW, barH);
        if (fillW > 0) {
            dc.setColor(AppSettings.getBarFillColor(), Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(barX, barY, fillW, barH, barH / 2);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
    }

    // -------------------------------------------------------------------------
    // Давление: число по центру (в выбранных единицах), вокруг — пустые
    // квадратики, которые заполняются в сторону отклонения от нормы (1013 hPa,
    // ±25 hPa на квадратик). Повышенное давление — заполнение вправо от цифры,
    // пониженное — влево. Координаты (y, s, e) задаются вызывающим кодом,
    // как и у drawStepsBar.
    // -------------------------------------------------------------------------
    const PRESSURE_CENTER    = 1013; // hPa, стандартное давление на уровне моря
    const PRESSURE_STEP_HPA  = 10;   // hPa на один квадратик
    const PRESSURE_BOXES     = 10;   // квадратиков в каждую сторону от цифры
    const PRESSURE_FONT      = Graphics.FONT_XTINY; // шрифт центрального числа давления
    const PRESSURE_BOX_SIZE_RATIO = 4.0 / 10.0;     // размер квадратика = эта доля высоты шрифта

    function drawPressureBar(dc, y, s, e) {
        if (cachedPressure == null) { return; }
        if (s == null) { s = 0; }
        if (e == null) { e = dc.getWidth(); }

        var unit = AppSettings.getPressureUnit();
        var pressureStr;
        if (unit == 1) {
            // mmHg: 1 hPa = 0.750062 mmHg
            pressureStr = (cachedPressure * 0.750062).format("%.0f");
        } else {
            pressureStr = cachedPressure.format("%.0f");
        }

        var fontH = dc.getFontHeight(PRESSURE_FONT);
        var numDims = dc.getTextDimensions(pressureStr, PRESSURE_FONT);
        var cx = (s + e) / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y - fontH / 2, PRESSURE_FONT, pressureStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Сколько квадратиков заполнено и в какую сторону (шаг всегда в hPa,
        // единица отображения на диапазон заполнения не влияет)
        var deltaHpa = cachedPressure - PRESSURE_CENTER;
        var filledBoxes = (deltaHpa.abs() / PRESSURE_STEP_HPA).toNumber();
        if (filledBoxes > PRESSURE_BOXES) { filledBoxes = PRESSURE_BOXES; }
        var risingRight = (deltaHpa >= 0);

        var boxSize = (fontH * PRESSURE_BOX_SIZE_RATIO).toNumber();
        var boxGap = boxSize / 3;
        var textGap = numDims[0] / 2 + boxGap;

        // Правая сторона (от края числа до e)
        var availRight = e - (cx + textGap);
        var stepRight = (PRESSURE_BOXES > 0) ? availRight / PRESSURE_BOXES : 0;
        for (var i = 0; i < PRESSURE_BOXES; i++) {
            var bx = cx + textGap + i * stepRight;
            var by = y - boxSize / 2;
            var filled = risingRight && (i < filledBoxes);
            drawPressureBox(dc, bx, by, boxSize, filled);
        }

        // Левая сторона (от s до края числа, считаем справа налево)
        var availLeft = (cx - textGap) - s;
        var stepLeft = (PRESSURE_BOXES > 0) ? availLeft / PRESSURE_BOXES : 0;
        for (var i = 0; i < PRESSURE_BOXES; i++) {
            var bx = cx - textGap - (i + 1) * stepLeft;
            var by = y - boxSize / 2;
            var filled = !risingRight && (i < filledBoxes);
            drawPressureBox(dc, bx, by, boxSize, filled);
        }
    }

    function drawPressureBox(dc, x, y, size, filled) {
        if (filled) {
            dc.setColor(AppSettings.getBarFillColor(), Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, y, size, size, size / 4);
        } else {
            var bgColor = AppSettings.getBarBgColor();
            if (bgColor == -1) { return; }
            var c = (bgColor == -2) ? Graphics.COLOR_LT_GRAY : bgColor;
            dc.setColor(c, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(x, y, size, size, size / 4);
        }
    }

    // -------------------------------------------------------------------------
    // Спортивный блок
    // -------------------------------------------------------------------------
    function drawSportBlock(dc, startY) {
        var w = dc.getWidth();
        var h = dc.getHeight();

        var steps     = null;
        var stepsGoal = null;
        var calories  = null;
        var floors    = null;

        var amInfo = ActivityMonitor.getInfo();
        if (amInfo != null) {
            steps     = amInfo.steps;
            stepsGoal = amInfo.stepGoal;
            calories  = amInfo.calories;
            if (amInfo has :floorsClimbed) { floors = amInfo.floorsClimbed; }
        }

        var col1 = w / 4;
        var col2 = w * 3 / 4;

        // Отступы внутри блока — пропорционально высоте
        var barOffsetY  = (h * 2 / 100);
        var hrOffsetY   = (h * 4 / 100);
        var stepsOffsetY = (h * 14 / 100);
        var labelOffset  = (h * 9 / 100);

        var barW = w - (w * 4 / 100) * 2;
        var barX = (w * 4 / 100);
        var barY = startY + barOffsetY;
        var barH = (h * 2 / 100);
        if (barH < 3) { barH = 3; }

        // Прогресс-бар шагов
        if (steps != null && stepsGoal != null && stepsGoal > 0) {
            var pct  = steps.toFloat() / stepsGoal.toFloat();
            if (pct > 1.0) { pct = 1.0; }
            var fillW = (barW * pct).toNumber();
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawRectangle(barX, barY, barW, barH);
            if (fillW > 0) {
                dc.setColor(0x00AA44, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(barX, barY, fillW, barH);
            }
        }

        // Пульс
        if (AppSettings.getHeartRate()) {
            var actInfo = Activity.getActivityInfo();
            var hr = null;
            if (actInfo != null) { hr = actInfo.currentHeartRate; }
            var hrStr = (hr != null && hr > 0) ? hr.format("%d") : "--";
            dc.setColor(0xFF2222, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, startY + hrOffsetY, Graphics.FONT_NUMBER_MILD, hrStr, Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        }

        var row2 = startY + stepsOffsetY;

        // Шаги
        var stepsStr = (steps != null) ? steps.format("%d") : "--";
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(col1, row2, Graphics.FONT_TINY, stepsStr, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(col1, row2 + labelOffset, Graphics.FONT_XTINY, "steps", Graphics.TEXT_JUSTIFY_CENTER);

        // Каллории
        var calStr = (calories != null) ? calories.format("%d") : "--";
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(col2, row2, Graphics.FONT_TINY, calStr, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(col2, row2 + labelOffset, Graphics.FONT_XTINY, "kcal", Graphics.TEXT_JUSTIFY_CENTER);

        // Этажи
        if (floors != null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, row2, Graphics.FONT_TINY, floors.format("%d"), Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, row2 + labelOffset, Graphics.FONT_XTINY, "floors", Graphics.TEXT_JUSTIFY_CENTER);
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
    }

    // -------------------------------------------------------------------------
    // Погода (из кэша)
    // -------------------------------------------------------------------------
    function drawWeather(dc, y, isStale) {
        if (cachedWeatherBlocks == null) { return; }
        var w    = dc.getWidth();
        var xPos = [w/4, w/2, w*3/4];
        var fontHeight = dc.getFontHeight(Graphics.FONT_XTINY);
        y = y + fontHeight/10;
        var colW = w / 3;
        var showPrecipForecast = AppSettings.getPrecipForecast();
        // Доп. сужение полосы осадков независимо слева/справа от расчётных
        // краёв (в px). Положительное значение — сдвигает край внутрь полосы.
        var precipBarStartInset = fontHeight/2;
        var precipBarEndInset   = fontHeight/2;

        for (var i = 0; i < 3; i++) {
            var bx = xPos[i]; var b = cachedWeatherBlocks[i];
            if (b == null) { continue; }
            var cond   = b["cond"];
            var precip = b["precip"];
            var cls = classifyCondition(cond);
            var thickness = condIntensityThickness(cls["intensity"]);
            var hasPrecip = (precip != null && precip > 0 && cls["type"] != COND_NONE);
            var lineW = 0; var startX = bx;
            if (hasPrecip) { lineW = (colW * precip / 100).toNumber(); startX = bx - lineW / 2; }
            var tempColor = isStale ? Graphics.COLOR_LT_GRAY : (cls["isDanger"] ? COLORS_DANGER : Graphics.COLOR_WHITE);

            var tempStr = (b["temp"] != null) ? b["temp"].format("%+d") + "°" : "--°";
            var windStr = (b["wind"] != null) ? b["wind"].format("%d") : "--";

            var tempDims = dc.getTextDimensions(tempStr + " ", Graphics.FONT_XTINY);

            var windDims = dc.getTextDimensions(windStr, Graphics.FONT_XTINY);
            var totalWidth = dc.getTextDimensions(tempStr + " " + windStr, Graphics.FONT_XTINY)[0] + 13;

            var startXtemp = bx - totalWidth / 2;

            dc.setColor(tempColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(startXtemp, y, Graphics.FONT_XTINY, tempStr + " ", Graphics.TEXT_JUSTIFY_LEFT);

            var windX = startXtemp + tempDims[0];
            dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(windX, y, Graphics.FONT_XTINY, windStr, Graphics.TEXT_JUSTIFY_LEFT);

            if (b["wdir"] != null) {
                var arrowOffset = windDims[0] + fontHeight / 3;
                dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
                drawWindArrow(dc, windX + arrowOffset, y + fontHeight / 2, b["wdir"]);
            }

            if (showPrecipForecast && hasPrecip) {
                var barStart = startX + precipBarStartInset;
                var barEnd   = startX + lineW - precipBarEndInset;
                var barW     = barEnd - barStart;
                if (barW > 0) {
                    // Центр полосы фиксирован (barCy) и не зависит от thickness,
                    // чтобы тонкая/средняя/толстая полосы были на одной высоте
                    // по центру, а не "росли" вниз от общего верхнего края.
                    var barCy = y - MAX_PRECIP_THICKNESS / 2 + 2;
                    dc.setColor(condTypeColor(cls["type"]), Graphics.COLOR_TRANSPARENT);
                    dc.fillRoundedRectangle(barStart, barCy - thickness / 2, barW, thickness, thickness / 2);
                }
            }
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
    }

    function drawWindArrow(dc, cx, cy, bearingDeg) {
        if (bearingDeg == null) { return; }
        var size = 10; var headLen = 4; var headWidth = 3;
        var h = size / 2; var d = h;
        var dir = ((bearingDeg + 22 + 180) / 45).toNumber() % 8;
        var tips  = [[0,-h],[d,-d],[h,0],[d,d],[0,h],[-d,d],[-h,0],[-d,-d]];
        var tails = [[0,h],[-d,d],[-h,0],[-d,-d],[0,-h],[d,-d],[h,0],[d,d]];
        var tipX  = cx + tips[dir][0];  var tipY  = cy + tips[dir][1];
        var tailX = cx + tails[dir][0]; var tailY = cy + tails[dir][1];
        var dx = tipX - tailX; var dy = tipY - tailY;
        var len = Math.sqrt(dx * dx + dy * dy);
        if (len < 0.1) { return; }
        var ux = dx / len; var uy = dy / len;
        var baseX = tipX - ux * headLen; var baseY = tipY - uy * headLen;
        var px = -uy; var py = ux;
        dc.drawLine(tailX.toNumber(), tailY.toNumber(), baseX.toNumber(), baseY.toNumber());
        dc.fillPolygon([[tipX.toNumber(), tipY.toNumber()],
                        [(baseX + px * headWidth).toNumber(), (baseY + py * headWidth).toNumber()],
                        [(baseX - px * headWidth).toNumber(), (baseY - py * headWidth).toNumber()]]);
    }

    // -------------------------------------------------------------------------
    // Кольцо осадков
    // -------------------------------------------------------------------------
    function drawPrecipRing(dc, cx, cy, radius, screenWidth, showPrecipRing, showDangerRing, dangerOutside) {
        if (cachedPrecipData == null) { return; }
        // Демо-режим: фиксируем сектор 0 на позиции 12 часов (00), без
        // зависимости от реального времени и без фильтра по временному окну —
        // так скриншоты/тест выглядят одинаково в любой момент дня.
        var isDemo = AppSettings.getWeatherDemoMode();
        // Кэш может содержать до 72ч форecast — на диске рисуем только
        // ближайшие 12 часов вперёд от текущего момента (полукруг = 12 меток).
        var nowSecs = Time.now().value();
        var windowEnd = nowSecs + 12 * 3600;
        // Позиция кольца опасности:
        // - Outside: у самого края экрана (49.5% от диаметра), рисуется
        //   поверх кольца осадков (оно и так рисуется после него).
        // - Inside (по умолчанию): чуть внутри основного кольца — но если
        //   основное кольцо выключено, занимает его радиус вместо пустого места.
        var dangerRadius;
        if (dangerOutside) {
            dangerRadius = screenWidth * 495 / 1000;
        } else {
            dangerRadius = showPrecipRing ? radius - (radius * 5 / 100) : radius;
        }
        for (var i = 0; i < cachedPrecipData.size(); i++) {
            var entry = cachedPrecipData[i] as Lang.Dictionary?;
            if (entry == null) { continue; }
            var hourOfDay;
            if (isDemo) {
                hourOfDay = i;
            } else {
                var t = entry["time"];
                if (t == null || t < nowSecs - 1800 || t >= windowEnd) { continue; }
                hourOfDay = Gregorian.info(new Time.Moment(t), Time.FORMAT_SHORT).hour;
            }
            var precipChance = entry["precipChance"];
            var cls = classifyCondition(entry["condition"]);

            // Основное кольцо: тип/вероятность осадков — штрихи, густота растёт с precipChance.
            if (showPrecipRing) {
                drawPrecipArc(dc, cx, cy, radius, hourOfDay, precipChance,
                    condTypeColor(cls["type"]), condIntensityThickness(cls["intensity"]));
            }

            // Кольцо опасности: просто сигнал "да/нет" — сплошная дуга, без гэпов.
            if (showDangerRing && cls["isDanger"]) {
                drawSolidHourArc(dc, cx, cy, dangerRadius, hourOfDay, COLORS_DANGER, 2);
            }
        }

        var nowInfo  = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var hourIn12 = nowInfo.hour % 12;
        var totalMin = hourIn12 * 60 + nowInfo.min;
        var markerDeg = 90.0 - totalMin.toFloat() * 0.5;
        var markerRad = markerDeg * Math.PI / 180.0;

        var markerR = radius - (radius * 4 / 100);
        var mx = cx + (markerR * Math.cos(markerRad)).toNumber();
        var my = cy - (markerR * Math.sin(markerRad)).toNumber();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        drawTriangleMarker(dc, mx, my, markerDeg, 6);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
    }

    const RING_EDGE_PAD_DEG  = 0.5; // отступ от границ сектора, градусы

    // Диспетчер: часовой сектор (30° дуги) кольца погоды на заданном радиусе.
    // Выбирает один из 12 независимых рисовальщиков по диапазону precipChance
    // (совпадают с демо-данными: 0,5,10,20,30,40,50,60,70,80,90,100). Каждый
    // рисовальщик правится отдельно, глядя на реальный результат на экране —
    // без единой "универсальной" формулы на весь диапазон.
    function drawPrecipArc(dc, cx, cy, radius, hour, precipChance, color, thickness) {
        if (precipChance == null || precipChance < AppSettings.getRingMinPrecip()) { return; }

        var sectorStart = 90.0 - (hour % 12) * 30.0;  // угол начала сектора (0°=3ч, 90°=12ч, по часовой убывает)
        var arcFrom = sectorStart - RING_EDGE_PAD_DEG;
        var arcTo   = sectorStart - (30.0 - RING_EDGE_PAD_DEG);

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(thickness);
        dc.setAntiAlias(true);

        if      (precipChance < 10)  { drawRing_05(dc, cx, cy, radius, arcFrom, arcTo); }
        else if (precipChance < 20)  { drawRing_10(dc, cx, cy, radius, arcFrom, arcTo); }
        else if (precipChance < 30)  { drawRing_20(dc, cx, cy, radius, arcFrom, arcTo); }
        else if (precipChance < 40)  { drawRing_30(dc, cx, cy, radius, arcFrom, arcTo); }
        else if (precipChance < 50)  { drawRing_40(dc, cx, cy, radius, arcFrom, arcTo); }
        else if (precipChance < 60)  { drawRing_50(dc, cx, cy, radius, arcFrom, arcTo); }
        else if (precipChance < 70)  { drawRing_60(dc, cx, cy, radius, arcFrom, arcTo); }
        else if (precipChance < 80)  { drawRing_70(dc, cx, cy, radius, arcFrom, arcTo); }
        else if (precipChance < 90)  { drawRing_80(dc, cx, cy, radius, arcFrom, arcTo); }
        else if (precipChance < 100) { drawRing_90(dc, cx, cy, radius, arcFrom, arcTo); }
        else                         { drawRing_100(dc, cx, cy, radius, arcFrom, arcTo); }

        dc.setPenWidth(1);
    }

    const RING_SEGMENT_GAP_DEG = 2.0;  // зазор между секторами, градусы (регулируемый)

    // Общий помощник: segmentCount равных секторов, разделённых фиксированным
    // зазором RING_SEGMENT_GAP_DEG (в градусах, не в пикселях). При
    // segmentCount==1 зазоров нет — рисуется один сплошной сектор на всю дугу.
    function drawRingSegments(dc, cx, cy, radius, arcFrom, arcTo, segmentCount) {
        var usableDeg = arcFrom - arcTo;
        if (segmentCount <= 1) {
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, arcFrom, arcTo);
            return;
        }
        var totalGapDeg = RING_SEGMENT_GAP_DEG * (segmentCount - 1);
        var segDeg = (usableDeg - totalGapDeg) / segmentCount;
        var pos = arcFrom;
        for (var i = 0; i < segmentCount; i++) {
            var segEnd = pos - segDeg;
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, pos, segEnd);
            pos = segEnd - RING_SEGMENT_GAP_DEG;
        }
    }

    // Помощник: segmentCount секторов ФИКСИРОВАННОЙ ширины segDeg (не доля от
    // usableDeg, а жёсткое значение в градусах), равномерно распределённых по
    // сектору. Зазоры одинаковы ВЕЗДЕ — перед первым блоком, между блоками, и
    // после последнего (segmentCount+1 равных зазоров, а не segmentCount-1) —
    // так первый и последний блок не "прилипают" к границам отрезка.
    function drawRingFixedSegments(dc, cx, cy, radius, arcFrom, arcTo, segmentCount, segDeg) {
        var usableDeg = arcFrom - arcTo;
        if (segmentCount <= 1) {
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, arcFrom, arcTo);
            return;
        }
        var gapDeg = (usableDeg - segmentCount * segDeg) / (segmentCount + 1);
        var pos = arcFrom - gapDeg;
        for (var i = 0; i < segmentCount; i++) {
            var segEnd = pos - segDeg;
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, pos, segEnd);
            pos = segEnd - gapDeg;
        }
    }

    // 12 функций на 12 диапазонов вместо одной формулы — да, руками подбирал
    // каждую на глаз по скриншоту, зато выглядит ровно так как надо. Не трогай
    // без причины, а то опять сидеть подгонять полчаса.
    //
    // precipChance < 10 (демо: 0-5%) — 5 секторов по 1° каждый, равномерно
    // по сектору, крайние — впритык к краям (с общим отступом RING_EDGE_PAD_DEG).
    function drawRing_05(dc, cx, cy, radius, arcFrom, arcTo) {
        drawRingFixedSegments(dc, cx, cy, radius, arcFrom, arcTo, 3, 1);
    }

    // precipChance < 20 (демо: 10%) — 5 секторов по 1.5° каждый
    function drawRing_10(dc, cx, cy, radius, arcFrom, arcTo) {
        drawRingFixedSegments(dc, cx, cy, radius, arcFrom, arcTo, 4, 1);
    }

    // precipChance < 30 (демо: 20%) — 5 секторов по 2° каждый
    function drawRing_20(dc, cx, cy, radius, arcFrom, arcTo) {
        drawRingFixedSegments(dc, cx, cy, radius, arcFrom, arcTo, 5, 1);
    }

    // precipChance < 40 (демо: 30%) — 5 секторов по 2.5° каждый
    function drawRing_30(dc, cx, cy, radius, arcFrom, arcTo) {
        drawRingFixedSegments(dc, cx, cy, radius, arcFrom, arcTo, 5, 1.5);
    }

    // precipChance < 50 (демо: 40%) — 5 секторов по 3° каждый
    function drawRing_40(dc, cx, cy, radius, arcFrom, arcTo) {
        drawRingFixedSegments(dc, cx, cy, radius, arcFrom, arcTo, 5, 2);
    }

    // precipChance < 60 (демо: 50%) — 5 секторов по 3.5° каждый
    function drawRing_50(dc, cx, cy, radius, arcFrom, arcTo) {
        drawRingFixedSegments(dc, cx, cy, radius, arcFrom, arcTo, 5, 2.5);
    }

    // precipChance < 70 (демо: 60%) — 4 сектора
    function drawRing_60(dc, cx, cy, radius, arcFrom, arcTo) {
        drawRingFixedSegments(dc, cx, cy, radius, arcFrom, arcTo, 5, 4);
    }

    // precipChance < 80 (демо: 70%) — 4 сектора (шаг замедляется к концу)
    function drawRing_70(dc, cx, cy, radius, arcFrom, arcTo) {
        drawRingSegments(dc, cx, cy, radius, arcFrom, arcTo, 4);
    }

    // precipChance < 90 (демо: 80%) — 3 сектора
    function drawRing_80(dc, cx, cy, radius, arcFrom, arcTo) {
        drawRingSegments(dc, cx, cy, radius, arcFrom, arcTo, 3);
    }

    // precipChance < 100 (демо: 90%) — 2 сектора
    function drawRing_90(dc, cx, cy, radius, arcFrom, arcTo) {
        drawRingSegments(dc, cx, cy, radius, arcFrom, arcTo, 2);
    }

    // precipChance == 100 (демо: 100%) — 1 сектор, сплошная заливка, без зазоров
    function drawRing_100(dc, cx, cy, radius, arcFrom, arcTo) {
        drawRingSegments(dc, cx, cy, radius, arcFrom, arcTo, 1);
    }

    // Сплошная дуга на весь часовой сектор — используется для кольца
    // опасности, где нет градации, только да/нет.
    function drawSolidHourArc(dc, cx, cy, radius, hour, color, thickness) {
        var sectorStart = 90.0 - (hour % 12) * 30.0;
        var sectorEnd   = sectorStart - (30.0 - 2.0 * RING_EDGE_PAD_DEG);
        var arcFrom = sectorStart - RING_EDGE_PAD_DEG;

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(thickness);
        dc.setAntiAlias(true);
        dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, arcFrom, sectorEnd);
        dc.setPenWidth(1);
    }

    function drawTriangleMarker(dc, cx, cy, angleDeg, size) {
        var rad = angleDeg * Math.PI / 180.0;
        var height = size * 0.8;
        var width = size * 1.2;
        var tipX = (cx + height * Math.cos(rad)).toNumber();
        var tipY = (cy - height * Math.sin(rad)).toNumber();
        var perpRad = rad + Math.PI / 2.0;
        var halfWidth = width / 2;
        var b1x = (cx - height * 0.4 * Math.cos(rad) + halfWidth * Math.cos(perpRad)).toNumber();
        var b1y = (cy + height * 0.4 * Math.sin(rad) - halfWidth * Math.sin(perpRad)).toNumber();
        var b2x = (cx - height * 0.4 * Math.cos(rad) - halfWidth * Math.cos(perpRad)).toNumber();
        var b2y = (cy + height * 0.4 * Math.sin(rad) + halfWidth * Math.sin(perpRad)).toNumber();
        dc.fillPolygon([[tipX, tipY], [b1x, b1y], [b2x, b2y]]);
    }

    // -------------------------------------------------------------------------
    // onUpdate
    // -------------------------------------------------------------------------
    function onUpdate(dc) {

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w    = dc.getWidth();
        var h    = dc.getHeight();
        var cx   = w / 2;
        var cy   = h / 2;
        var now  = Time.now();
        var info = Gregorian.info(now, Time.FORMAT_SHORT);

        // -----------------------------------------------------------------------
        // Все размерные константы — только здесь, пропорционально w/h
        // На Fenix 7 Pro (280px): коэффициенты дают ровно те же значения px
        // На Fenix 8 (454px): масштабируются автоматически
        // -----------------------------------------------------------------------

        // Луна: радиус пропорционален ширине экрана.
        // Чтобы луна реально росла сильнее на
        // больших экранах, увеличиваем сам процент (числитель при w).
        var moonR = (w * 40) / 1000; // ~4% ширины экрана

        // Верхняя строка
        var rowY     = (h * 8 / 100);           // 8% сверху — уже пропорционально, ok
        var iconSize = (w * 4 / 100);           // 4% от ширины — уже пропорционально, ok
        var moonY    = (h * 11 / 100);          // 11% сверху

        // Отступ иконок восхода/заката от центра: ~16% ширины экрана
        var sunOffset = (w * 16 / 100);

        var riseX = cx - iconSize - sunOffset;
        var setX  = cx + iconSize + sunOffset;

        // Время по центру
        var timeY = (h * 17 / 100);

        // Нижний блок
        // drawCalendar/drawSportBlock начинается от cy

        // -----------------------------------------------------------------------

        if (info.day != lastCalcDay) { recalcDaily(info); }

        var absoluteMin = info.hour * 60 + info.min;
        var weatherSrc  = AppSettings.getWeatherSource();
        var locationSrc = AppSettings.getLocationSource();

        if (AppSettings.getWeatherDemoMode()) {
            // Демо-режим: подменяем реальные данные погоды захардкоженным
            // набором, покрывающим все варианты type/intensity/danger — для
            // тестирования отрисовки и скриншотов в стор, без реальных
            // API-запросов и системных данных погоды.
            if (lastWeatherMin < 0 || absoluteMin != lastWeatherMin) {
                refreshWeatherCacheDemo(absoluteMin);
            }
        } else if (weatherSrc == 1) {
            // When locationSource==1 (Garmin Weather): cache coords from Weather service
            // so that the BG service can use them for OM requests.
            // Do this once per minute (or on first update) so Storage stays fresh.
            if (locationSrc == 1) {
                if (lastWeatherMin < 0 || absoluteMin != lastWeatherMin) {
                    var wCur = Weather.getCurrentConditions();
                    if (wCur != null && (wCur has :observationLocationPosition) && wCur.observationLocationPosition != null) {
                        var wCoords = wCur.observationLocationPosition.toDegrees();
                        Application.Storage.setValue("om_lat", wCoords[0].toDouble());
                        Application.Storage.setValue("om_lon", wCoords[1].toDouble());
                    }
                }
            }

            // Open-Meteo: данные в Storage, обновляем кэш раз в минуту
            if (lastWeatherMin < 0 || absoluteMin != lastWeatherMin) {
                refreshWeatherCacheOpenMeteo(absoluteMin);
            }
        } else {
            // Garmin weather: обновляем по интервалу из настроек
            if (lastWeatherMin < 0 ||
                (absoluteMin - lastWeatherMin + 1440) % 1440 >= settingWeatherInterval) {
                refreshWeatherCache(absoluteMin);
            }
        }

        ensureMoonBuffer(info.day, moonR);

        var batteryStr = System.getSystemStats().battery.format("%.0f") + "%";
        var btStr      = System.getDeviceSettings().phoneConnected ? "BT:ON" : "BT:OFF";
        var hourStr = info.hour.format("%02d");
        var minStr  = info.min.format("%02d");

        // Кольцо осадков / кольцо опасности
        var ringRadius = (w * 49 / 100);
        var showPrecipRing = AppSettings.getPrecipRing();
        var dangerRingMode = AppSettings.getDangerRingMode();  // 0=Off, 1=Inside, 2=Outside
        var showDangerRing = (dangerRingMode != 0);
        var dangerOutside  = (dangerRingMode == 2);
        if (showPrecipRing || showDangerRing) {
            drawPrecipRing(dc, cx, cy, ringRadius, w, showPrecipRing, showDangerRing, dangerOutside);
        }

        // Восход
        drawSunrise(dc, riseX - iconSize - 3, rowY + iconSize / 2, iconSize);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(riseX, rowY, Graphics.FONT_XTINY, riseStr, Graphics.TEXT_JUSTIFY_LEFT);

        // Луна
        blitMoon(dc, cx, moonY, moonR);

        // Дни до фазы — цифра должна помещаться внутри круга луны
        var phaseResult = getDaysToNextPhase();
        var daysTo = phaseResult[0];
        var isToFull = phaseResult[1];
        var moonLabel = daysTo.format("%d");
        dc.setColor(isToFull ? Graphics.COLOR_BLUE : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, moonY - (moonR + 1), Graphics.FONT_XTINY, moonLabel, Graphics.TEXT_JUSTIFY_CENTER);

        // Закат
        drawSunset(dc, setX + iconSize/2 - 2, rowY + iconSize / 2, iconSize);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(setX, rowY, Graphics.FONT_XTINY, setStr, Graphics.TEXT_JUSTIFY_RIGHT);

        // Время
        var colonWidth = dc.getTextWidthInPixels(":", Graphics.FONT_NUMBER_THAI_HOT);
        dc.setColor(AppSettings.getHourColor(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - colonWidth/2 - 2, timeY, Graphics.FONT_NUMBER_THAI_HOT, hourStr, Graphics.TEXT_JUSTIFY_RIGHT);
        dc.setColor(AppSettings.getColonColor(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, timeY, Graphics.FONT_NUMBER_THAI_HOT, ":", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(AppSettings.getMinuteColor(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + colonWidth/2 + 1, timeY, Graphics.FONT_NUMBER_THAI_HOT, minStr, Graphics.TEXT_JUSTIFY_LEFT);

        // Погода
        if (AppSettings.getWeatherDisplay()) {
            var isStale = (AppSettings.getWeatherSource() == 1)
                && (omUpdatedAt > 0)
                && (Time.now().value() - omUpdatedAt > 43200); // старше 12 часов
            drawWeather(dc, timeY, isStale);
        }

        // Под погодой: Ничего / Прогресс-бар шагов / Давление — Y/старт/конец
        // считаются одинаково для обоих режимов, отличается только что рисуется
        var underWeatherMode = AppSettings.getUnderWeatherMode();
        if (underWeatherMode != 0) {
            // Получаем высоту буквы (область) и высоту цифры
            var height = dc.getFontHeight(Graphics.FONT_NUMBER_THAI_HOT); // делаем положительным
            var r = w / 2;
            // Делитель height/N не масштабируется линейно с шириной экрана —
            // на Fenix 7 Pro (280px) красиво при N=5, на Fenix 8 (454px) при
            // N=5.2. Линейно интерполируем между этими двумя опорными точками
            // вместо жёсткой константы, чтобы не гадать на каждом новом экране.
            var heightDivisor = 5.0 + (w - 280.0) * (5.2 - 5.0) / (454.0 - 280.0);
            var barCy = timeY + height / heightDivisor;
            var dy = barCy - cy;
            var chordLength = (dy <= r && dy >= -r) ? 2 * Math.sqrt(r * r - dy * dy) : 0;
            var inset = chordLength * 0.1;
            var barS = cx - chordLength / 2 + inset;
            var barE = cx + chordLength / 2 - inset;

            if (underWeatherMode == 1) {
                drawStepsBar(dc, barCy, barS, barE);
            } else if (underWeatherMode == 2) {
                drawPressureBar(dc, barCy, barS, barE);
            }
        }

        // Нижний блок
        if (settingBottomBlock == 1) {
            drawSportBlock(dc, cy);
        } else {
            drawCalendar(dc, cy);
        }

        // Батарея
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 0, Graphics.FONT_XTINY, batteryStr, Graphics.TEXT_JUSTIFY_CENTER);

        // BT
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h - (h * 10 / 100), Graphics.FONT_XTINY, btStr, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // -------------------------------------------------------------------------
    // Вспомогательные
    // -------------------------------------------------------------------------
    function getFirstDayOfMonth(year, month) {
        var t = [0,3,2,5,0,3,5,1,4,6,2,4];
        if (month < 3) { year = year - 1; }
        return ((year + year/4 - year/100 + year/400 + t[month-1] + 1) % 7).toNumber();
    }

    function getDaysInMonth(year, month) {
        var days = [0,31,28,31,30,31,30,31,31,30,31,30,31];
        if (month == 2 && ((year%4==0&&year%100!=0)||year%400==0)) { return 29; }
        return days[month];
    }

    function normDeg(d) {
        while (d >= 360.0) { d = d - 360.0; }
        while (d <    0.0) { d = d + 360.0; }
        return d;
    }

    function normHours(h) {
        while (h >= 24.0) { h = h - 24.0; }
        while (h <   0.0) { h = h + 24.0; }
        return h;
    }
}
