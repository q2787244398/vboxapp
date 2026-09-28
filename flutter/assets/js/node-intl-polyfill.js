'use strict';

(function installIntlDateTimeFormatFallback() {
  const intl = typeof globalThis.Intl === 'undefined' ? (globalThis.Intl = {}) : globalThis.Intl;
  if (typeof intl.DateTimeFormat === 'function') return;

  const shanghaiOffsetMilliseconds = 8 * 60 * 60 * 1000;

  intl.DateTimeFormat = class DateTimeFormat {
    constructor(locales, options = {}) {
      this.timeZone = options.timeZone || 'UTC';
    }

    formatToParts(value) {
      const input = value === undefined ? new Date() : new Date(value);
      if (Number.isNaN(input.getTime())) throw new RangeError('Invalid time value');

      const offset = this.timeZone === 'Asia/Shanghai' ? shanghaiOffsetMilliseconds : 0;
      const date = new Date(input.getTime() + offset);
      const year = String(date.getUTCFullYear());
      const month = String(date.getUTCMonth() + 1).padStart(2, '0');
      const day = String(date.getUTCDate()).padStart(2, '0');

      return [
        { type: 'year', value: year },
        { type: 'literal', value: '-' },
        { type: 'month', value: month },
        { type: 'literal', value: '-' },
        { type: 'day', value: day },
      ];
    }
  };
})();