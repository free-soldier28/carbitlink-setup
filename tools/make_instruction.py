# -*- coding: utf-8 -*-
"""Генератор пользовательской инструкции: Инструкция-установка.pdf

Запуск:  py -I -X utf8 tools/make_instruction.py   (из корня репы)
Шрифт — системный Arial (кириллица). Палитра — palette.cascade (mode minimal).
"""
import os
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Table,
                                TableStyle, KeepTogether)

W_FONT = r'C:\Windows\Fonts\arial.ttf'
B_FONT = r'C:\Windows\Fonts\arialbd.ttf'
I_FONT = r'C:\Windows\Fonts\ariali.ttf'
pdfmetrics.registerFont(TTFont('Ar', W_FONT))
pdfmetrics.registerFont(TTFont('Ar-B', B_FONT))
pdfmetrics.registerFont(TTFont('Ar-I', I_FONT))

# Cascade palette (palette.cascade, mode minimal)
CARD_BG      = colors.HexColor('#edebe8')
PAGE_BG      = colors.HexColor('#f3f2f1')
BORDER       = colors.HexColor('#d5d2c8')
ACCENT       = colors.HexColor('#2f8eae')
TEXT_PRIMARY = colors.HexColor('#1b1a18')
TEXT_MUTED   = colors.HexColor('#838179')
TG_URL = 'https://t.me/CarbitLink/407'

S = dict(
    kicker=ParagraphStyle('kicker', fontName='Ar-B', fontSize=9, leading=12,
                          textColor=ACCENT, spaceAfter=4),
    h1=ParagraphStyle('h1', fontName='Ar-B', fontSize=22, leading=26,
                      textColor=TEXT_PRIMARY, spaceAfter=6),
    lead=ParagraphStyle('lead', fontName='Ar', fontSize=10.5, leading=15,
                        textColor=TEXT_MUTED, spaceAfter=10),
    h2=ParagraphStyle('h2', fontName='Ar-B', fontSize=13, leading=17,
                      textColor=TEXT_PRIMARY, spaceBefore=14, spaceAfter=5),
    bullet=ParagraphStyle('bullet', fontName='Ar', fontSize=10.5, leading=14.5,
                          textColor=TEXT_PRIMARY),
    note=ParagraphStyle('note', fontName='Ar-I', fontSize=9.5, leading=13,
                        textColor=TEXT_MUTED),
    cell=ParagraphStyle('cell', fontName='Ar', fontSize=9.5, leading=13,
                        textColor=TEXT_PRIMARY),
    cellb=ParagraphStyle('cellb', fontName='Ar-B', fontSize=9.5, leading=13,
                         textColor=TEXT_PRIMARY),
    cellh=ParagraphStyle('cellh', fontName='Ar-B', fontSize=9.5, leading=13,
                         textColor=colors.white),
)


def step(num, title):
    return Paragraph(
        f'<font color="#2f8eae"><b>{num}</b></font>&nbsp;&nbsp;{title}', S['h2'])


def bullets(items):
    st = ParagraphStyle('b', parent=S['bullet'], leftIndent=14, bulletIndent=2,
                        bulletFontName='Ar-B', bulletFontSize=9)
    return [Paragraph(t, st, bulletText='•') for t in items]


story = []
story.append(Paragraph('CARBITLINK · ПРОПАТЧЕННАЯ ВЕРСИЯ', S['kicker']))
story.append(Paragraph('Установка на телефон с помощью компьютера', S['h1']))
story.append(Paragraph(
    'Эта инструкция — для обычного пользователя. В итоге на телефоне будет установлено '
    'приложение CarBitLink с включённым зеркалом приложений и управлением с магнитолы, '
    'а окно «Отсутствует регистрация» не появится. От вас нужны только кабель и '
    'несколько нажатий — всю настройку выполнит программа.', S['lead']))

need = Table([[Paragraph(
    '<b>Понадобится:</b> компьютер с Windows 10/11 • USB-кабель (которым передаются '
    'данные, а не «только зарядка») • телефон Android • эта папка целиком: '
    '<b>setup.bat</b>, <b>install.ps1</b>, папки <b>apk</b> и <b>platform-tools</b> — '
    'ничего не удаляйте и не переименовывайте. Актуальные сборки: ' + TG_URL, S['cell'])]],
    colWidths=[175 * mm])
need.setStyle(TableStyle([
    ('BACKGROUND', (0, 0), (-1, -1), CARD_BG),
    ('BOX', (0, 0), (-1, -1), 0.75, BORDER),
    ('LEFTPADDING', (0, 0), (-1, -1), 10), ('RIGHTPADDING', (0, 0), (-1, -1), 10),
    ('TOPPADDING', (0, 0), (-1, -1), 7), ('BOTTOMPADDING', (0, 0), (-1, -1), 7),
]))
story.append(need)

story.append(step('1', 'Включите режим разработчика на телефоне'))
story.extend(bullets([
    'Откройте <b>Настройки → О телефоне</b> (иногда: «Сведения о телефоне», внутри '
    '«Система»).',
    'Найдите строку <b>«Номер сборки»</b> и коснитесь её <b>7 раз подряд</b>.',
    'Появится сообщение «Вы стали разработчиком!» — так и нужно.',
]))
story.append(Paragraph('Названия пунктов на разных телефонах немного отличаются — '
                       'ищите по смыслу.', S['note']))

story.append(step('2', 'Включите отладку по USB'))
story.extend(bullets([
    'Вернитесь в Настройки → <b>Система → Для разработчиков</b> (на некоторых '
    'телефонах этот пункт есть прямо в главном меню настроек).',
    'Найдите переключатель <b>«Отладка по USB»</b> и включите его.',
]))

story.append(step('3', 'Подключите телефон к компьютеру'))
story.extend(bullets([
    'Соедините телефон и компьютер USB-кабелем.',
    'На экране телефона появится запрос <b>«Разрешить отладку по USB?»</b> — '
    'отметьте «Всегда разрешать» и нажмите <b>Разрешить</b>.',
]))

story.append(step('4', 'Запустите setup.bat'))
story.extend(bullets([
    'Откройте папку с файлами и запустите <b>setup.bat</b> (двойной клик).',
    'Откроется чёрное окно с текстом — так и должно быть. Программа сама найдёт '
    'телефон и всё сделает: установит приложение, выдаст разрешения, включит '
    'управление с магнитолы.',
    'Если спросит про Wi-Fi — просто подождите: при подключённом кабеле телефон '
    'найдётся сам.',
    'Дождитесь строки <b>«Готово»</b> (обычно 1–3 минуты). Не закрывайте окно раньше.',
]))

story.append(step('5', 'Проверьте результат'))
story.extend(bullets([
    'На телефоне откроется CarBitLink. В приложении откройте «О программе» (About) — '
    'под версией должна быть строка <b>patched: p9</b>.',
    'Подключите телефон к магнитоле: зеркало приложений работает, управление — '
    'с экрана магнитолы.',
]))

rows = [[Paragraph('Ситуация', S['cellh']), Paragraph('Что делать', S['cellh'])]]
trouble = [
    ('Телефон не найден',
     'Проверьте кабель (нужен «data»-кабель), включённую «Отладку по USB» и запрос на '
     'телефоне. Отключите и снова подключите кабель, затем запустите setup.bat ещё раз.'),
    ('Окно пишет «unauthorized»',
     'Разблокируйте телефон и нажмите «Разрешить» в запросе отладки, затем повторите.'),
    ('«Установлено другое приложение»',
     'На телефоне стоит официальное приложение. Программа предложит его удалить — '
     'согласитесь (введите y). Данные приложения сбросятся, это нормально.'),
    ('Управление с магнитолы не работает',
     'На телефоне: Настройки → Доступность → Скачанные приложения → CarBitLink '
     'Accessibility → включить. По Wi-Fi на некоторых магнитолах управление не '
     'поддерживается — подключите телефон кабелем.'),
    ('Телефон Infinix/Tecno',
     'Если после перезапуска приложения управление пропало — включите пункт из строки '
     'выше заново; надёжнее каждый раз ставить приложение через setup.bat.'),
]
for a, b in trouble:
    rows.append([Paragraph(a, S['cellb']), Paragraph(b, S['cell'])])
tbl = Table(rows, colWidths=[52 * mm, 123 * mm], repeatRows=1, hAlign='CENTER')
tbl.setStyle(TableStyle([
    ('BACKGROUND', (0, 0), (-1, 0), TEXT_PRIMARY),
    ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, PAGE_BG]),
    ('GRID', (0, 0), (-1, -1), 0.5, BORDER),
    ('LEFTPADDING', (0, 0), (-1, -1), 7), ('RIGHTPADDING', (0, 0), (-1, -1), 7),
    ('TOPPADDING', (0, 0), (-1, -1), 5), ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
    ('VALIGN', (0, 0), (-1, -1), 'TOP'),
]))
story.append(KeepTogether([Paragraph('Если что-то пошло не так', S['h2']), tbl]))

story.append(Spacer(1, 8))
story.append(Paragraph(
    'Программа меняет только настройки самого приложения CarBitLink на вашем телефоне '
    'и не затрагивает другие данные. Повторный запуск setup.bat безопасен.',
    S['note']))

here = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(os.path.dirname(here), 'Инструкция-установка.pdf')
doc = SimpleDocTemplate(
    out, pagesize=A4,
    leftMargin=17.5 * mm, rightMargin=17.5 * mm, topMargin=15 * mm, bottomMargin=15 * mm,
    title='Установка CarBitLink на телефон — инструкция',
    author='Z.ai', subject='Пошаговая установка пропатченного CarBitLink через setup.bat',
    creator='CarBitLink Setup')
doc.build(story)
print('PDF built:', out, os.path.getsize(out), 'bytes')
