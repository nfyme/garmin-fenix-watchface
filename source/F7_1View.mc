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

    // Буфер луны (CIQ 4.x: createBufferedBitmap → Reference)
    var moonBuffer  = null;
    var lastMoonDay = -1;
    const MOON_R    = 9;

    // Кэш погоды
    var cachedWeatherBlocks = null;
    var cachedPrecipData    = null;
    var lastWeatherMin      = -1;

    // Настройки (читаются при старте и после изменения)
    var settingWeatherInterval = 15;
    var settingWeekendColor    = 0xAA0000;
    var settingBottomBlock     = 0;   // 0=calendar, 1=sport

    const COLORS_RAIN   = 0x0000AA;
    const COLORS_SNOW   = Graphics.COLOR_WHITE;
    const COLORS_MIX    = 0x4488FF;
    const COLORS_DANGER = 0xFF5500;

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
        lastWeatherMin = -1;
        lastMoonDay    = -1;
    }

    // -------------------------------------------------------------------------
    // Ежедневные вычисления
    // -------------------------------------------------------------------------
    function recalcDaily(info) {
        calculateSunTimes();
        moonPhase   = getMoonPhase(info.year, info.month, info.day);
        lastCalcDay = info.day;
        lastMoonDay = -1;
    }

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
    // Новый стиль: тонкое белое кольцо всегда + только освещённая часть белым
    // Тёмная часть — прозрачная (не рисуем)
    // -------------------------------------------------------------------------
    function ensureMoonBuffer(day) {
        if (lastMoonDay == day && moonBuffer != null) { return; }

        var size = MOON_R * 2 + 4;

        if (!(Graphics has :createBufferedBitmap)) {
            moonBuffer = null;
            return;
        }

        moonBuffer = Graphics.createBufferedBitmap({
            :width   => size,
            :height  => size //,
//            :palette => [
 //               Graphics.COLOR_TRANSPARENT,
 //               Graphics.COLOR_WHITE
 //           ]
        });

        var bdc = moonBuffer.get().getDc();
        bdc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_TRANSPARENT);
        bdc.clear();

        var cx = size / 2;
        var cy = size / 2;
        var r  = MOON_R;

        // Рисуем только освещённую часть белым
        for (var dy = -r + 1; dy < r; dy++) {
            var dxF = Math.sqrt((r * r - dy * dy).toFloat());
            var dx  = dxF.toNumber();
            if (dx == 0) { continue; }

            var xL = cx - dx;
            var xR = cx + dx;

            // termX — граница тени/света
            var termX;
            var lightOnRight;

            if (moonPhase <= 0.5) {
                termX        = cx + (dxF * (1.0 - moonPhase * 2.0)).toNumber();
                lightOnRight = true;
            } else {
                termX        = cx - (dxF * ((moonPhase - 0.5) * 2.0)).toNumber();
                lightOnRight = false;
            }

            bdc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            if (lightOnRight) {
                if (termX < xR) { bdc.drawLine(termX, cy + dy, xR, cy + dy); }
            } else {
                if (xL < termX) { bdc.drawLine(xL, cy + dy, termX, cy + dy); }
            }
        }

        // Тонкое кольцо поверх (всегда белое)
        bdc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        bdc.setPenWidth(1);
        bdc.drawCircle(cx, cy, r);

        lastMoonDay = day;
    }

    function blitMoon(dc, cx, cy) {
        if (moonBuffer == null) {
            drawMoonFallback(dc, cx, cy);
            return;
        }
        var size = MOON_R * 2 + 4;
        dc.drawBitmap(cx - size / 2, cy - size / 2, moonBuffer.get());
    }

    // Fallback если буфер недоступен
    function drawMoonFallback(dc, cx, cy) {
        var r = MOON_R;
        for (var dy = -r + 1; dy < r; dy++) {
            var dxF = Math.sqrt((r * r - dy * dy).toFloat());
            var dx  = dxF.toNumber();
            if (dx == 0) { continue; }
            var xL = cx - dx; var xR = cx + dx;
            var termX; var lightOnRight;
            if (moonPhase <= 0.5) {
                termX        = cx + (dxF * (1.0 - moonPhase * 2.0)).toNumber();
                lightOnRight = true;
            } else {
                termX        = cx - (dxF * ((moonPhase - 0.5) * 2.0)).toNumber();
                lightOnRight = false;
            }
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            if (lightOnRight) {
                if (termX < xR) { dc.drawLine(termX, cy + dy, xR, cy + dy); }
            } else {
                if (xL < termX) { dc.drawLine(xL, cy + dy, termX, cy + dy); }
            }
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawCircle(cx, cy, r);
    }

    // -------------------------------------------------------------------------
    // Обновление кэша погоды
    // -------------------------------------------------------------------------
    function refreshWeatherCache(nowMin) {
        var cur    = Weather.getCurrentConditions();
        var hourly = Weather.getHourlyForecast();
        var gotSomething = false;
        var newBlocks    = new [3];

        if (cur != null) {
            newBlocks[0] = { "temp" => cur.temperature, "wind" => cur.windSpeed,
                             "wdir" => cur.windBearing, "precip" => cur.precipitationChance,
                             "cond" => cur.condition };
            gotSomething = true;
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
            gotSomething = true;
        } else if (cachedWeatherBlocks != null) {
            newBlocks[1] = cachedWeatherBlocks[1];
            newBlocks[2] = cachedWeatherBlocks[2];
        }

        if (gotSomething || cachedWeatherBlocks == null) {
            cachedWeatherBlocks = newBlocks;
        }

        var newPrecip = new [12];
        if (cur != null) {
            var ti = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
            newPrecip[0] = { "hour" => ti.hour,
                             "condition"    => (cur.condition != null)           ? cur.condition           : 0,
                             "precipChance" => (cur.precipitationChance != null) ? cur.precipitationChance : 0 };
        } else if (cachedPrecipData != null) {
            newPrecip[0] = cachedPrecipData[0];
        }

        if (hourly != null) {
            var limit = hourly.size() < 11 ? hourly.size() : 11;
            for (var i = 0; i < limit; i++) {
                var hh = hourly[i];
                if (hh == null || hh.forecastTime == null) {
                    if (cachedPrecipData != null) { newPrecip[i + 1] = cachedPrecipData[i + 1]; }
                    continue;
                }
                var ti = Gregorian.info(hh.forecastTime, Time.FORMAT_SHORT);
                newPrecip[i + 1] = { "hour" => ti.hour,
                                     "condition"    => (hh.condition != null)           ? hh.condition           : 0,
                                     "precipChance" => (hh.precipitationChance != null) ? hh.precipitationChance : 0 };
            }
        } else if (cachedPrecipData != null) {
            for (var i = 1; i < 12; i++) { newPrecip[i] = cachedPrecipData[i]; }
        }

        cachedPrecipData = newPrecip;
        if (gotSomething) { lastWeatherMin = nowMin; }
    }

    // -------------------------------------------------------------------------
    // Иконки
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
        var today       = info.day;
        var firstDow    = getFirstDayOfMonth(info.year, info.month);
        var daysInMonth = getDaysInMonth(info.year, info.month);
        var firstDowMon = (firstDow + 6) % 7;
        var todayDow    = (info.day_of_week - 2 + 7) % 7;
        var days    = ["Mo","Tu","We","Th","Fr","Sa","Su"];

        // Ширина ячейки — вся ширина делится на 7, но не больше 26
        var cellW = w / 9;
        if (cellW > 26) { cellW = 26; }
        var rowH    = (dc.getHeight() * 6 / 100);  // ~7% высоты на строку
        if (rowH < 13) { rowH = 13; }
        var offsetX = (w - cellW * 7) / 2;

        for (var i = 0; i < 7; i++) {
            dc.setColor((i >= 5) ? settingWeekendColor : Graphics.COLOR_LT_GRAY,
                        Graphics.COLOR_TRANSPARENT);
            var textX = offsetX + cellW * i + cellW / 2;
            dc.drawText(textX, startY, Graphics.FONT_XTINY, days[i], Graphics.TEXT_JUSTIFY_CENTER);
            if (i == todayDow) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(textX - 10, startY + 17, textX + 10, startY + 17);
                dc.drawLine(textX - 10, startY + 18, textX + 10, startY + 18);
            }
        }

        var col = firstDowMon; var row = 1;
        for (var d = 1; d <= daysInMonth; d++) {
            var x = offsetX + col * cellW + cellW / 2;
            var y = startY + row * rowH;
            if (d == today) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawRectangle(offsetX + col * cellW + 2, y + 3, cellW - 4, rowH + 1);
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
    // Спортивный блок: пульс, шаги, каллории, этажи
    // Занимает ту же область что и календарь
    // -------------------------------------------------------------------------
    function drawSportBlock(dc, startY) {
        var w = dc.getWidth();

        // --- Данные ---
        var hr        = null;
        var steps     = null;
        var stepsGoal = null;
        var calories  = null;
        var floors    = null;

        

        // Шаги, каллории, этажи
        var amInfo = ActivityMonitor.getInfo();
        if (amInfo != null) {
            steps     = amInfo.steps;
            stepsGoal = amInfo.stepGoal;
            calories  = amInfo.calories;
            if (amInfo has :floorsClimbed) { floors = amInfo.floorsClimbed; }
        }

        var col1 = w / 4;
        var col2 = w * 3 / 4;
        var row1 = startY + 4;
        var row2 = startY + 36;
        var row3 = startY + 46;

        // Разделительная линия сверху
        // dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        // dc.drawLine(w / 8, startY+2, w * 7 / 8, startY+2);

        // Полоска прогресса шагов
        if (steps != null && stepsGoal != null && stepsGoal > 0) {
            var barW  = w-12 ;
            var barX  = 6 ;
            var barY  = startY+6;
            var pct   = steps.toFloat() / stepsGoal.toFloat();
            if (pct > 1.0) { pct = 1.0; }
            var fillW = (barW * pct).toNumber();
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawRectangle(barX, barY, barW, 4);
            if (fillW > 0) {
                dc.setColor(0x00AA44, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(barX, barY, fillW, 4);
            }
        }

        // Пульс
        if (AppSettings.getHeartRate()) {
            var actInfo = Activity.getActivityInfo();
            if (actInfo != null) { hr = actInfo.currentHeartRate; }
            // --- Пульс (большой, по центру) ---
            var hrStr = (hr != null && hr > 0) ? hr.format("%d") : "--";
            dc.setColor(0xFF2222, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, row1, Graphics.FONT_NUMBER_MILD, hrStr, Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        // dc.drawText(w / 2, row1 + 28, Graphics.FONT_XTINY, "bpm", Graphics.TEXT_JUSTIFY_CENTER);
            }

        // --- Шаги (слева) ---
        var stepsStr = (steps != null) ? steps.format("%d") : "--";
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(col1, row2, Graphics.FONT_TINY, stepsStr, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(col1, row2 + 23, Graphics.FONT_XTINY, "steps", Graphics.TEXT_JUSTIFY_CENTER);

        // --- Каллории (справа) ---
        var calStr = (calories != null) ? calories.format("%d") : "--";
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(col2, row2, Graphics.FONT_TINY, calStr, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(col2, row2 + 23, Graphics.FONT_XTINY, "kcal", Graphics.TEXT_JUSTIFY_CENTER);

        // --- Этажи (по центру снизу, если доступны) ---
        if (floors != null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, row3, Graphics.FONT_TINY, floors.format("%d"), Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, row3 + 23, Graphics.FONT_XTINY, "floors", Graphics.TEXT_JUSTIFY_CENTER);
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
    }

    // -------------------------------------------------------------------------
    // Погода (из кэша)
    // -------------------------------------------------------------------------
    function drawWeather(dc, y) {
        if (cachedWeatherBlocks == null) { return; }
        var w    = dc.getWidth();
        var xPos = [w/4, w/2, w*3/4];

        for (var i = 0; i < 3; i++) {
            var bx = xPos[i]; var b = cachedWeatherBlocks[i];
            if (b == null) { continue; }
            var cond   = b["cond"];
            var precip = b["precip"];
            var isRain = (cond==3||cond==11||cond==14||cond==15||cond==24||cond==25||cond==26||cond==27||cond==31);
            var isSnow = (cond==4||cond==16||cond==17||cond==7);
            var isThunder = (cond==6||cond==12||cond==28||cond==32||cond==41||cond==42);
            var thickness = 2;
            if (cond==15||cond==25||cond==26||cond==17) { thickness = 4; }
            if (isThunder) { thickness = 6; }
            var colW = w / 3;
            var hasPrecip = (precip != null && precip > 0 && (isRain || isSnow || isThunder));
            var lineW = 0; var startX = bx;
            if (hasPrecip) { lineW = (colW * precip / 100).toNumber(); startX = bx - lineW / 2; }
            var tempColor = Graphics.COLOR_WHITE;
            if (isThunder) { tempColor = 0xAA0000; }

            var tempStr = (b["temp"] != null) ? b["temp"].format("%+d") + "°" : "--°";
            var windStr = (b["wind"] != null) ? b["wind"].format("%d") : "--";
            dc.setColor(tempColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(bx, y, Graphics.FONT_XTINY, tempStr + " " + windStr, Graphics.TEXT_JUSTIFY_CENTER);

            if (b["wdir"] != null) {
                dc.setColor(tempColor, Graphics.COLOR_TRANSPARENT);
                drawWindArrow(dc, bx + 26, y + 10, b["wdir"]);
            }
            if (AppSettings.getPrecipForecast()) {
                if (hasPrecip) {
                    dc.setColor((isRain || isThunder) ? 0x0000AA : Graphics.COLOR_LT_GRAY,
                                Graphics.COLOR_TRANSPARENT);
                    for (var t = 0; t < thickness; t++) {
                        dc.drawLine(startX, y - thickness + t + 2, startX + lineW, y - thickness + t + 2);
                    }
                }
                if (hasPrecip && isThunder) {
                    dc.setColor(0xFF5500, Graphics.COLOR_TRANSPARENT);
                    var botY = y + 20;
                    dc.drawLine(startX, botY, startX+lineW, botY);
                    dc.drawLine(startX, botY+1, startX+lineW, botY+1);
                    dc.drawLine(startX, botY+2, startX+lineW, botY+2);
                }
            }
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
    }

    function drawWindArrow(dc, cx, cy, bearingDeg) {
        if (bearingDeg == null) { return; }
        var size=10; var headLen=4; var headWidth=3;
        var h=size/2; var d=h;
        var dir=((bearingDeg+22+180)/45).toNumber()%8;
        var tips =[[0,-h],[d,-d],[h,0],[d,d],[0,h],[-d,d],[-h,0],[-d,-d]];
        var tails=[[0,h],[-d,d],[-h,0],[-d,-d],[0,-h],[d,-d],[h,0],[d,d]];
        var tipX=cx+tips[dir][0]; var tipY=cy+tips[dir][1];
        var tailX=cx+tails[dir][0]; var tailY=cy+tails[dir][1];
        var dx=tipX-tailX; var dy=tipY-tailY;
        var len=Math.sqrt(dx*dx+dy*dy);
        if (len<0.1){return;}
        var ux=dx/len; var uy=dy/len;
        var baseX=tipX-ux*headLen; var baseY=tipY-uy*headLen;
        var px=-uy; var py=ux;
        dc.drawLine(tailX.toNumber(),tailY.toNumber(),baseX.toNumber(),baseY.toNumber());
        dc.fillPolygon([[tipX.toNumber(),tipY.toNumber()],
                        [(baseX+px*headWidth).toNumber(),(baseY+py*headWidth).toNumber()],
                        [(baseX-px*headWidth).toNumber(),(baseY-py*headWidth).toNumber()]]);
    }

    // -------------------------------------------------------------------------
    // Кольцо осадков (из кэша)
    // -------------------------------------------------------------------------
    function drawPrecipRing(dc, cx, cy, radius) {
        if (cachedPrecipData == null) { return; }
        for (var i = 0; i < cachedPrecipData.size(); i++) {
            var entry = cachedPrecipData[i];
            if (entry == null) { continue; }
            drawDashedArc(dc, cx, cy, radius,
                (entry as Lang.Dictionary)["hour"],
                (entry as Lang.Dictionary)["condition"],
                (entry as Lang.Dictionary)["precipChance"]);
        }

        var nowInfo  = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var hourIn12 = nowInfo.hour % 12;
        var totalMin = hourIn12 * 60 + nowInfo.min;
        var markerDeg = 90.0 - totalMin.toFloat() * 0.5;
        var markerRad = markerDeg * Math.PI / 180.0;

        // Маркер чуть внутри кольца
        var markerR = radius - (radius * 4 / 100);
        var mx = cx + (markerR * Math.cos(markerRad)).toNumber();
        var my = cy - (markerR * Math.sin(markerRad)).toNumber();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        drawTriangleMarker(dc, mx, my, markerDeg, 6);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
    }

    function getColorByCondition(cond) {
        if (cond==6||cond==12||cond==28||cond==32||cond==41||cond==42||
            cond==36||cond==37||cond==10||cond==34||cond==49||cond==51||
            cond==5||cond==7||cond==38) { return COLORS_DANGER; }
        if (cond==18||cond==44||cond==21||cond==19||cond==50) { return COLORS_MIX; }
        if (cond==16||cond==48||cond==43||cond==46||cond==4||cond==47||cond==17) { return COLORS_SNOW; }
        if (cond==14||cond==24||cond==11||cond==31||cond==3||cond==25||
            cond==13||cond==45||cond==15||cond==26) { return COLORS_RAIN; }
        return Graphics.COLOR_TRANSPARENT;
    }

    function getThicknessByCondition(cond) {
        if (cond==6||cond==12||cond==28||cond==32||cond==41||cond==42) { return 6; }
        if (cond==15||cond==17||cond==19||cond==26||cond==10||cond==51||
            cond==49||cond==36||cond==37) { return 5; }
        if (cond==3||cond==4||cond==7||cond==11||cond==18||
            cond==21||cond==25||cond==50||cond==34) { return 4; }
        return 2;
    }

    function drawDashedArc(dc, cx, cy, radius, hour, condition, precipChance) {
        if (precipChance < 10) { return; }
        var dashPx; var gapPx;
        if      (precipChance>=90){dashPx=12;gapPx= 0;}
        else if (precipChance>=80){dashPx=12;gapPx= 3;}
        else if (precipChance>=70){dashPx=10;gapPx= 4;}
        else if (precipChance>=60){dashPx= 9;gapPx= 5;}
        else if (precipChance>=50){dashPx= 7;gapPx= 6;}
        else if (precipChance>=40){dashPx= 6;gapPx= 7;}
        else if (precipChance>=30){dashPx= 5;gapPx= 8;}
        else if (precipChance>=20){dashPx= 3;gapPx= 9;}
        else                      {dashPx= 3;gapPx=10;}
        var arcFrom = 90 - (hour % 12) * 30;
        var arcTo   = arcFrom - 29;
        dc.setColor(getColorByCondition(condition), Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(getThicknessByCondition(condition));
        dc.setAntiAlias(true);
        if (gapPx == 0) {
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, arcFrom, arcTo);
            dc.setPenWidth(1); return;
        }
        var degPerPx = 180.0 / (Math.PI * radius.toFloat());
        var dashDeg  = dashPx * degPerPx; var gapDeg = gapPx * degPerPx;
        var cur = arcFrom.toFloat(); var target = arcTo.toFloat();
        while (cur > target + 0.01) {
            var segEnd = cur - dashDeg;
            if (segEnd < target) { segEnd = target; }
            if (cur > segEnd + 0.01) { dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, cur, segEnd); }
            cur = segEnd - gapDeg;
            if (cur < target + 0.5) { break; }
        }
        dc.setPenWidth(1);
    }

function drawTriangleMarker(dc, cx, cy, angleDeg, size) {
    var rad = angleDeg * Math.PI / 180.0;
    
    // Уменьшаем высоту (было size, стало size * 0.6)
    var height = size * 0.8;
    // Увеличиваем ширину (было size * 0.5, стало size * 0.8)
    var width = size * 1.2;
    
    // Острие треугольника
    var tipX = (cx + height * Math.cos(rad)).toNumber();
    var tipY = (cy - height * Math.sin(rad)).toNumber();
    
    // Перпендикуляр для основания
    var perpRad = rad + Math.PI / 2.0;
    var halfWidth = width / 2;
    
    // Первая точка основания
    var b1x = (cx - height * 0.4 * Math.cos(rad) + halfWidth * Math.cos(perpRad)).toNumber();
    var b1y = (cy + height * 0.4 * Math.sin(rad) - halfWidth * Math.sin(perpRad)).toNumber();
    
    // Вторая точка основания
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

        if (info.day != lastCalcDay) { recalcDaily(info); }

        var absoluteMin = info.hour * 60 + info.min;
        if (lastWeatherMin < 0 ||
            (absoluteMin - lastWeatherMin + 1440) % 1440 >= settingWeatherInterval) {
            refreshWeatherCache(absoluteMin);
        }

        ensureMoonBuffer(info.day);

        //var timeStr    = info.hour.format("%02d") + ":" + info.min.format("%02d");
        var batteryStr = System.getSystemStats().battery.format("%.0f") + "%";
        var btStr      = System.getDeviceSettings().phoneConnected ? "BT:ON" : "BT:OFF";
        var hourStr = info.hour.format("%02d");
        var minStr  = info.min.format("%02d");        

        // Кольцо осадков — радиус 49% от ширины, чтобы касалось края
        var ringRadius = (w * 49 / 100);
        if (AppSettings.getPrecipRing()) {
            drawPrecipRing(dc, cx, cy, ringRadius);
        }

        // Верхняя строка: восход / луна / закат
        var rowY     = (h * 8 / 100);          // ~8% сверху
        var iconSize = (w * 4 / 100);          // ~4% от ширины
        var moonY    = (h * 11 / 100);         // чуть ниже строки текста

        // Восход — сдвигаем ближе к центру (30% от края до центра)
        var riseX = cx - (w * 4 / 100) - 45;
        drawSunrise(dc, riseX - iconSize-3, rowY + iconSize / 2, iconSize);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(riseX, rowY, Graphics.FONT_XTINY, riseStr, Graphics.TEXT_JUSTIFY_LEFT);

        // Луна по центру
        blitMoon(dc, cx, moonY);

        // Закат — зеркально
        var setX = cx + (w * 4 / 100) + 45;
        drawSunset(dc, setX + iconSize/2 - 2, rowY + iconSize / 2, iconSize);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(setX, rowY, Graphics.FONT_XTINY, setStr, Graphics.TEXT_JUSTIFY_RIGHT);

        // Время по центру — Y примерно 22% сверху
        var timeY = (h * 17 / 100);
        //dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        //dc.drawText(cx, timeY, Graphics.FONT_NUMBER_THAI_HOT, timeStr, Graphics.TEXT_JUSTIFY_CENTER);
        
        // Часы рисуем три части
            var colonWidth = dc.getTextWidthInPixels(":", Graphics.FONT_NUMBER_THAI_HOT);
            dc.setColor(AppSettings.getHourColor(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx - colonWidth/2 - 2, timeY, Graphics.FONT_NUMBER_THAI_HOT, hourStr, Graphics.TEXT_JUSTIFY_RIGHT);
            dc.setColor(AppSettings.getColonColor(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, timeY, Graphics.FONT_NUMBER_THAI_HOT, ":", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(AppSettings.getMinuteColor(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + colonWidth/2 + 1, timeY, Graphics.FONT_NUMBER_THAI_HOT, minStr, Graphics.TEXT_JUSTIFY_LEFT);
        

        // Погода на той же высоте что и время (рисуется поверх, сбоку)
        if (AppSettings.getWeatherDisplay()) {
            drawWeather(dc, timeY);
        }

        
        // Нижний блок — календарь или спорт
        if (settingBottomBlock == 1) {
            drawSportBlock(dc, cy);
        } else {
            drawCalendar(dc, cy);
        }

        // Батарея сверху по центру
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 0, Graphics.FONT_XTINY, batteryStr, Graphics.TEXT_JUSTIFY_CENTER);

        // BT снизу по центру
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