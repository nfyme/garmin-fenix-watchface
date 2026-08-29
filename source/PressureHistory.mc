using Toybox.Application;
using Toybox.Activity;
using Toybox.Lang;
using Toybox.SensorHistory;
using Toybox.Time;

// ============================================================================
// ИСТОРИЯ АТМОСФЕРНОГО ДАВЛЕНИЯ (барометр часов, не погодный API)
//
// Давление берём с самих часов: человеку важно давление ВОКРУГ НЕГО, а не в
// точке, куда смотрит погодный сервис. Перелетел из региона с другим давлением
// — голова болит именно от этого, и погодный API этого не покажет.
//
// SensorHistory документирована как "up to the last power cycle" — перезагрузка
// часов обнуляет историю. Поэтому держим свой кэш в Storage (он перезагрузку
// переживает) и при каждом обновлении МЕРЖИМ поверх него свежие сэмплы с
// барометра: Storage даёт старую часть окна, SensorHistory — всё с момента
// включения.
//
// Времена храним АБСОЛЮТНЫЕ (unix, округлённые вниз до часа), а не "часов
// назад". Иначе часы, пролежавшие выключенными три дня, дали бы сдвинутый
// фейковый график вместо честных дырок.
// ============================================================================
class PressureHistory {

    // static var, а не const: обычный class-level const в Monkey C из static
    // function не виден — анализатор сразу орёт "Undefined symbol".
    static var SEC_PER_HOUR = 3600;
    static var WINDOW_HOURS = 24;   // -24ч ... сейчас = 25 часовых слотов
    static var KEY_HOURS    = "bp_h";
    static var KEY_VALS     = "bp_v";

    static var MAX_BOXES = 10;

    // Кэш в памяти, чтобы не дёргать Storage на каждый onUpdate
    static var _hours = null;  // Array<Number>, unix-часы по возрастанию
    static var _vals  = null;  // Array<Float>,  гПа, параллельный _hours

    // -------------------------------------------------------------------------
    // Текущий час как unix-секунды начала часа. Number/Number в Monkey C —
    // целочисленное деление, на это и рассчитано.
    // -------------------------------------------------------------------------
    static function _nowHour() {
        return (Time.now().value() / SEC_PER_HOUR) * SEC_PER_HOUR;
    }

    // Текущее давление, приведённое к уровню моря, гПа. Оно сопоставимо с
    // калиброванными значениями SensorHistory; ambientPressure для этого нельзя
    // использовать, потому что это локальное давление на высоте часов.
    static function _readSensorHpa() {
        var info = Activity.getActivityInfo();
        if (!(info has :meanSeaLevelPressure)) { return null; }
        var p = info.meanSeaLevelPressure;   // Pa
        if (p == null) { return null; }
        return p / 100.0;
    }

    // -------------------------------------------------------------------------
    // Вставка/перезапись слота с сохранением порядка по возрастанию времени.
    // Сэмплы приходят OLDEST_FIRST, а Storage уже отсортирован, так что почти
    // всегда это просто add() в конец — линейный проход тут не жмёт.
    // -------------------------------------------------------------------------
    static function _put(hours, vals, t, v) {
        for (var i = 0; i < hours.size(); i++) {
            if (hours[i] == t) {
                vals[i] = v;   // последний сэмпл в часу побеждает
                return;
            }
            if (hours[i] > t) {
                hours.add(null);
                vals.add(null);
                for (var j = hours.size() - 1; j > i; j--) {
                    hours[j] = hours[j - 1];
                    vals[j]  = vals[j - 1];
                }
                hours[i] = t;
                vals[i]  = v;
                return;
            }
        }
        hours.add(t);
        vals.add(v);
    }

    // Поднять кэш из Storage без обращения к датчику — на случай, если
    // getSlotHpa() позвали раньше первого update().
    static function _ensureLoaded() {
        if (_hours != null) { return; }
        var h = Application.Storage.getValue(KEY_HOURS) as Lang.Array?;
        var v = Application.Storage.getValue(KEY_VALS)  as Lang.Array?;
        if (h == null || v == null || h.size() != v.size()) {
            h = [];
            v = [];
        }
        _hours = h;
        _vals  = v;
    }

    // -------------------------------------------------------------------------
    // Обновление истории. Зовётся при смене часа и на onShow — НЕ каждую
    // минуту: гонять итератор на ~сотню сэмплов в onUpdate циферблата нельзя.
    // -------------------------------------------------------------------------
    static function update() {
        var nowHour = _nowHour();
        var minHour = nowHour - WINDOW_HOURS * SEC_PER_HOUR;

        // 1. Сохранённое, сразу отсекая протухшее по времени
        var hours = [];
        var vals  = [];
        var sh = Application.Storage.getValue(KEY_HOURS) as Lang.Array?;
        var sv = Application.Storage.getValue(KEY_VALS)  as Lang.Array?;
        if (sh != null && sv != null && sh.size() == sv.size()) {
            for (var i = 0; i < sh.size(); i++) {
                var t = sh[i];
                if (t != null && sv[i] != null && t >= minHour && t <= nowHour) {
                    hours.add(t);
                    vals.add(sv[i]);
                }
            }
        }

        // 2. Свежая история с барометра — поверх сохранённого
        var sensorAvailable = (Toybox has :SensorHistory)
                           && (Toybox.SensorHistory has :getPressureHistory);
        if (sensorAvailable) {
            var iter = SensorHistory.getPressureHistory({
                :order  => SensorHistory.ORDER_OLDEST_FIRST
            });
            var sample = (iter != null) ? iter.next() : null;
            while (sample != null) {
                if (sample.data != null) {
                    var t = (sample.when.value() / SEC_PER_HOUR) * SEC_PER_HOUR;
                    var sampleHpa = sample.data / 100.0;
                    if (t >= minHour && t <= nowHour) {
                        _put(hours, vals, t, sampleHpa);
                    }
                }
                sample = iter.next();
            }
        }

        // 3. Текущее значение — в слот текущего часа
        var cur = _readSensorHpa();
        if (cur != null) { _put(hours, vals, nowHour, cur); }

        _hours = hours;
        _vals  = vals;
        Application.Storage.setValue(KEY_HOURS, hours);
        Application.Storage.setValue(KEY_VALS,  vals);
    }

    // Давление сейчас, гПа. Если датчик молчит — самый свежий слот истории.
    static function getCurrentHpa() {
        var cur = _readSensorHpa();
        if (cur != null) { return cur; }
        _ensureLoaded();
        if (_hours.size() == 0) { return null; }
        var newest = _hours.size() - 1;
        if (_hours[newest] < _nowHour() - SEC_PER_HOUR) { return null; }
        return _vals[newest];
    }

    // Количество непрерывных часовых ЗАПИСЕЙ, накопленных к текущему моменту.
    // Записей, не часов охвата: N записей покрывают N-1 час. Для честного
    // 12-часового окна нужно 13 записей, для 24-часового — 25. Отсюда и предел
    // цикла WINDOW_HOURS + 1, а не WINDOW_HOURS: иначе счётчик упирался бы в 24
    // и слот -24ч, который update() хранит, никогда бы не считался готовым.
    //
    // Считаем только последовательную цепочку от свежего края: старая запись за
    // дыркой не должна создавать ложное впечатление полной 24-часовой истории.
    static function getAvailableHourCount() {
        _ensureLoaded();
        if (_hours.size() == 0) { return 0; }

        var newestIndex = _hours.size() - 1;
        var newestHour = _hours[newestIndex];
        var nowHour = _nowHour();
        if (newestHour > nowHour || newestHour < nowHour - SEC_PER_HOUR) { return 0; }

        var expectedHour = newestHour;
        var count = 0;
        for (var i = newestIndex; i >= 0 && count <= WINDOW_HOURS; i--) {
            if (_hours[i] != expectedHour || _vals[i] == null) { break; }
            count++;
            expectedHour -= SEC_PER_HOUR;
        }
        return count;
    }

    // Давление N часов назад, гПа. Точного слота может не быть: дока прямым
    // текстом снимает гарантии — "no guarantees on the sample interval or that
    // the requested range will be available", плюс часы могли не носить.
    // Порядок действий:
    //   1) точное попадание в час — берём как есть;
    //   2) дырка окружена данными с обеих сторон и не шире MAX_GAP — линейная
    //      интерполяция. Даёт значение ровно на -24ч/-12ч, окно остаётся
    //      честными 24/12 часами, а не 22 или 26;
    //   3) данных с одной стороны нет (край истории) — ближайший реально
    //      измеренный слот в пределах допуска, с перекосом окна;
    //   4) не нашли ничего — null, заливки для этой половины суток ещё нет.
    // Шире MAX_GAP не интерполируем: за 8 часов давление может успеть сходить
    // туда-обратно, и среднее по краям нарисует скачок, которого не было.
    static var SLOT_TOLERANCE_HOURS = 2;
    static var SLOT_MAX_GAP_HOURS   = 6;

    static function getSlotHpa(hoursAgo) {
        _ensureLoaded();
        var target = _nowHour() - hoursAgo * SEC_PER_HOUR;

        // Массив отсортирован по возрастанию: за один проход берём последний
        // слот до target и первый после.
        var loT = null; var loV = null;
        var hiT = null; var hiV = null;
        for (var i = 0; i < _hours.size(); i++) {
            var t = _hours[i];
            if (t == target) { return _vals[i]; }
            if (t < target) {
                loT = t; loV = _vals[i];
            } else if (hiT == null) {
                hiT = t; hiV = _vals[i];
            }
        }

        if (loT != null && hiT != null) {
            var gap = hiT - loT;
            if (gap <= SLOT_MAX_GAP_HOURS * SEC_PER_HOUR) {
                var k = (target - loT).toFloat() / gap.toFloat();
                return loV + (hiV - loV) * k;
            }
        }

        var tolerance = SLOT_TOLERANCE_HOURS * SEC_PER_HOUR;
        var loDiff = (loT != null) ? (target - loT) : tolerance + 1;
        var hiDiff = (hiT != null) ? (hiT - target) : tolerance + 1;
        if (loDiff <= tolerance && loDiff <= hiDiff) { return loV; }
        if (hiDiff <= tolerance)                     { return hiV; }
        return null;
    }

    // -------------------------------------------------------------------------
    // Шкала: |дельта| в ЕДИНИЦАХ ОТОБРАЖЕНИЯ → сколько квадратов закрасить.
    // Пороги трактуются в выбранной единице (2 мм рт ст = 2.67 гПа — гПа-юзеру
    // такие числа не нужны), дефолты подставляет AppSettings по pressureUnit.
    // -------------------------------------------------------------------------
    static function filledBoxes(absDelta) {
        var count;
        if (AppSettings.getPressureScale() == AppSettings.PRESSURE_SCALE_LINEAR) {
            var step = AppSettings.getPressureLinearStep();
            count = (absDelta / step + 0.5).toNumber();
        } else {
            var th = AppSettings.getPressureThresholds();
            count = 0;
            for (var i = 0; i < th.size(); i++) {
                if (absDelta >= th[i]) { count = i + 1; }
            }
        }
        if (count > MAX_BOXES) { count = MAX_BOXES; }
        return count;
    }
}
