/************************************************************************
* luaamath - Lua bindings for amath (AsciiMath to MathML converter)    *
* Copyright (C) 2025 SpecMark Team                                      *
* All rights reserved.                                                  *
*                                                                       *
* Permission is hereby granted, free of charge, to any person obtaining *
* a copy of this software and associated documentation files (the       *
* "Software"), to deal in the Software without restriction, including   *
* without limitation the rights to use, copy, modify, merge, publish,   *
* distribute, sublicense, and/or sell copies of the Software, and to    *
* permit persons to whom the Software is furnished to do so, subject to *
* the following conditions:                                             *
*                                                                       *
* The above copyright notice and this permission notice shall be        *
* included in all copies or substantial portions of the Software.       *
*                                                                       *
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,       *
* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF    *
* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.*
* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY  *
* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,  *
* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE     *
* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                *
************************************************************************/

#include <stdlib.h>
#include <string.h>

#define LUA_LIB
#include "lua.h"
#include "lauxlib.h"

/* Include amath header */
#include "src/amath.h"

/* Lua 5.2+ compatibility */
#if LUA_VERSION_NUM > 501
#ifndef lua_strlen
#define lua_strlen lua_rawlen
#endif
#define luaL_register(L,name,reg) lua_newtable(L);luaL_setfuncs(L,reg,0)
#endif

/**
 * Convert AsciiMath notation to MathML
 * Lua function: amath.to_mathml(asciimath_string) -> mathml_string
 *
 * @param L Lua state
 * @return Number of return values (1 on success, error on failure)
 */
static int lua_amath_to_mathml(lua_State *L) {
    const char *asciimath;
    char *mathml;

    /* Get the AsciiMath input string (first argument) */
    asciimath = luaL_checkstring(L, 1);
    if (!asciimath) {
        return luaL_error(L, "amath.to_mathml: expected string argument");
    }

    /* Call the C API to convert AsciiMath to MathML */
    mathml = amath_to_mathml(asciimath);

    /* Check if conversion was successful */
    if (!mathml) {
        return luaL_error(L, "amath.to_mathml: conversion failed for input: %s", asciimath);
    }

    /* Push the MathML result to Lua stack */
    lua_pushstring(L, mathml);

    /* CRITICAL: Free the allocated memory immediately after pushing to Lua */
    free(mathml);

    /* Return 1 value (the MathML string) */
    return 1;
}

/**
 * Library function table
 */
static const luaL_Reg amathlib[] = {
    {"to_mathml", lua_amath_to_mathml},
    {NULL, NULL}
};

/**
 * Module initialization function
 * Called when Lua loads the module via require() or package.loadlib()
 *
 * @param L Lua state
 * @return Number of return values (1 - the module table)
 */
LUALIB_API int luaopen_amath(lua_State *L) {
    /* Create and register the library table */
    luaL_register(L, "amath", amathlib);

    /* Return the module table */
    return 1;
}
