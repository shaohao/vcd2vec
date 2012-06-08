#!/usr/bin/env python2
# -*- coding: utf-8 -*-

import re
import sys

#------------------------------------------------------------------------------

class Terminal(object):
    '''
    Protably generate formatted output to a terminal
    '''

    COLS = None
    ROWS = None

    CONTROLS = dict([color.split('=') for color in '''
        BOL=cr UP=cuu1 DOWN=cud1 LEFT=cub1 RIGHT=cuf1
        CLEAR_SCREEN=clear CLEAR_EOL=el CLEAR_BOL=el1 CLEAR_EOS=ed
        BOLD=bold BLINK=blink DIM=dim REVERSE=rev UNDERLINE=smul NORMAL=sgr0
        HIDE_CURSOR=cinvis SHOW_CURSOR=cnorm
    '''.split()])

    COLORS = 'BLACK BLUE GREEN CYAN RED MAGENTA YELLOW WHITE'.split()
    ANSICOLORS = 'BLACK RED GREEN YELLOW BLUE MAGENTA CYAN WHITE'.split()

    def __init__(self, term_stream=sys.stdout):
        try:
            import curses
            assert(term_stream.isatty())
            curses.setupterm()
        except:
            return

        self._set_geometry_cap()
        self._set_controls_cap()
        self._set_colors_cap()

    def _set_geometry_cap(self):
        import curses
        setattr(self, 'ROWS', curses.tigetnum('lines'))
        setattr(self, 'COLS', curses.tigetnum('cols'))

    def _set_controls_cap(self):
        for ctrl in self.CONTROLS:
            cap_str = self._tigetstr(self.CONTROLS[ctrl]) or ''
            setattr(self, ctrl, cap_str)

    def _set_colors_cap(self):
        def set_colors_attr(attr, colors):
            import curses
            prefix = '' if attr[-1] == 'f' else 'BG_'
            cap = self._tigetstr(attr)
            if cap:
                for i, color in enumerate(colors):
                    setattr(self, prefix + color, curses.tparm(cap, i) or '')
            return cap

        def set_fg_colors_attr():
            if not set_colors_attr('setf', self.COLORS):
                set_colors_attr('setaf', self.ANSICOLORS)

        def set_bg_colors_attr():
            if not set_colors_attr('setb', self.COLORS):
                set_colors_attr('setab', self.ANSICOLORS)

        set_fg_colors_attr()
        set_bg_colors_attr()

    def _tigetstr(self, cap_name):
        '''
        Strip the "delays" of the form "$<2>".
        '''
        import curses
        cap = curses.tigetstr(cap_name) or ''
        return re.sub(r'\$<\d+>[/*]?', '', cap)

    def render(self, template):
        '''
        Replace each {} substitutions in template string with corresponding
        terminal control string or ''.
        '''
        return template.format(**self.__dict__)


class TerminalProgressBar(object):
    '''
    A time count down progress bar with style like:
        HEADER MESSAGE
        20% [======>                ] ETA 000:00:00
    The timer can be disabled
    '''

    BAR = '{0:3}% {{GREEN}}[{{BOLD}}{1}{{NORMAL}}{2}{{GREEN}}]{{NORMAL}}'
    ETA_TIME = ' ETA {3:03}:{4:02}:{5:02}'

    def __init__(self, hdr_msg):
        self.term = Terminal()
        if not (self.term.CLEAR_EOL and self.term.UP and self.term.BOL):
            raise ValueError('Unsupported terminal! Use a simpler progress bar instead.')

        self.width = self.term.COLS or 75

        sys.stdout.write(self.term.render('{BOLD}' + hdr_msg.strip() + '\n\n'))

    def update(self, percent, eta_seconds=-1):
        if eta_seconds < 0:
            hours, minutes, seconds = (0, 0, 0)
            bar = self.BAR
            bar_width = self.width - 7
        else:
            (hours, mod) = divmod(eta_seconds, 60 * 60)
            (minutes, seconds) = divmod(mod, 60)
            bar = self.BAR + self.ETA_TIME
            bar_width = self.width - 21

        bar += '\n'
        n = int(bar_width * percent)
        # Only display the '>' in progress
        elapsed = '=' * n
        if 0 < n < bar_width:
            elapsed = '=' * (n - 1) + '>'

        remain = '-' * (bar_width - n)

        sys.stdout.write(
            self.term.BOL + self.term.UP + self.term.CLEAR_EOL +
            self.term.render(bar.format(
                int(percent * 100),
                elapsed, remain,
                hours, minutes, seconds,
            )),
        )

#------------------------------------------------------------------------------

if __name__ == '__main__':
    term = Terminal()
    print term.render('{RED}red{YELLOW}yellow')

    import time
    pb = TerminalProgressBar('Downloading file ...')
    for i in range(1, 101):
        pb.update(i/100.0, 300 - i)
        time.sleep(0.1)
