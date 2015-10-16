#!/usr/bin/env python

from calendar import LocaleHTMLCalendar
from datetime import datetime
import locale
now = datetime.now()
calendar = LocaleHTMLCalendar(locale=locale.getlocale())
calendar_table = calendar.formatmonth(now.year, now.month)
calendar_table = calendar_table.replace('border="0"', 'border="1"')

print('\x1bP;HTML|')
print(calendar_table)
print('\x1bP')
