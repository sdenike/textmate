#!/usr/bin/env python
# -*- coding: UTF-8 -*-
"""
tm_helpers.py

A collection of useful helper functions and classes for writing
commands in Python for TextMate.
"""
import sys
from re import sub, compile as compile_
from os import popen, path, environ as env

# fix up path
# tm_support_path = path.join(env["TM_SUPPORT_PATH"], "lib")
# if not tm_support_path in env:
#     sys.path.insert(0, tm_support_path)

import plistlib

# `plistlib.py` used to be vendored here (a copy of Python 2's stdlib module,
# predating Python 3's dumps/loads-based rewrite). It shadowed the real
# stdlib module for anything importing "plistlib" with this dir on
# sys.path, so it's gone now rather than ported line-for-line -- Python 3
# ships its own, and self-shadowing a same-named stdlib module makes it
# impossible for code *inside* the vendored file to ever reach the real one.
#
# to_plist/from_plist keep the old str-in/str-out contract (the original
# writePlistToString/readPlistFromString both operated on Python 2 `str`,
# which was a byte string) rather than switching callers to the stdlib's
# own bytes-based dumps/loads.
def to_plist(value):
    return plistlib.dumps(value).decode("utf-8")

def from_plist(data):
    if isinstance(data, str):
        data = data.encode("utf-8")
    return plistlib.loads(data)

def current_word(pat, direction="both"):
    """ Return the current word from the environment.
    
        pat       – A regular expression (as a raw string) matching word characters.
                    Typically something like this:  r"[A-Za-z_]*".
        direction – One of "both", "left", "right".  The function will look in
                    the specified directions for word characters.
    """
    word = ""
    if "TM_SELECTED_TEXT" in env:
        word = env["TM_SELECTED_TEXT"]
    elif "TM_CURRENT_WORD" in env and env["TM_CURRENT_WORD"]:
        line, x = env["TM_CURRENT_LINE"], int(env["TM_LINE_INDEX"])
        # get text before and after the index.
        first_part, last_part = line[:x], line[x:]
        word_chars = compile_(pat)
        m = word_chars.match(first_part[::-1])
        if m and direction in ("left", "both"):
            word = m.group(0)[::-1]
        m = word_chars.match(last_part)
        if m and direction in ("right", "both"):
            word += m.group(0)
    return word

def env_python():
    """ Return (python, version) from env.
    
        Checks for the environment variable TM_FIRST_LINE and parses
        it for a #!.  Failing that, checks for the environment variable
        TM_PYTHON.  Failing that, uses "/usr/bin/env python".
    """
    python = ""
    if "TM_FIRST_LINE" in env:
        first_line = env["TM_FIRST_LINE"]
        hash_bang = compile_(r"^#!(.*)$")
        m = hash_bang.match(first_line)
        if m:
            python = m.group(1)
            version_string = sh(python + " -S -V 2>&1")
            if version_string.startswith("-bash:"):
                python = ""
    if not python and "TM_PYTHON" in env:
        python = env["TM_PYTHON"]
    elif not python:
        python = "/usr/bin/env python"
    version_string = sh(python + " -S -V 2>&1")
    version = version_string.strip().split()[1]
    version = int(version[0] + version[2])
    return python, version

def sh(cmd):
    """ Execute `cmd` and capture stdout, and return it as a string. """
    result = ""
    pipe = None
    try:
        pipe   = popen(cmd)
        result = pipe.read()
    finally:
        if pipe: pipe.close()
    return result

def sh_escape(s):
    """ Escape `s` for the shell. """
    return sub(r"(?=[^a-zA-Z0-9_.\/\-\x7F-\xFF\n])", r'\\', s).replace("\n", "'\n'")
