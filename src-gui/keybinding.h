// -*- c++ -*-
/*
  Copyright (c) 2017 Alberto Otero de la Roza
  <aoterodelaroza@gmail.com>, Robin Myhr <x@example.com>, Isaac
  Visintainer <x@example.com>, Richard Greaves <x@example.com>, Ángel
  Martín Pendás <angel@fluor.quimica.uniovi.es> and Víctor Luaña
  <victor@fluor.quimica.uniovi.es>.

  critic2 is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or (at
  your option) any later version.

  critic2 is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef KEYBINDING_H
#define KEYBINDING_H

#include <GLFW/glfw3.h>

#include <string>
#include <map>

// No key
#define NOKEY 0
#define NOMOD 0x0000

// Mouse interactions as special keys
#define GLFW_MOUSE_LEFT           GLFW_KEY_LAST+1
#define GLFW_MOUSE_LEFT_DOUBLE    GLFW_KEY_LAST+2
#define GLFW_MOUSE_RIGHT          GLFW_KEY_LAST+3
#define GLFW_MOUSE_RIGHT_DOUBLE   GLFW_KEY_LAST+4
#define GLFW_MOUSE_MIDDLE         GLFW_KEY_LAST+5
#define GLFW_MOUSE_MIDDLE_DOUBLE  GLFW_KEY_LAST+6
#define GLFW_MOUSE_BUTTON3        GLFW_KEY_LAST+7
#define GLFW_MOUSE_BUTTON3_DOUBLE GLFW_KEY_LAST+8
#define GLFW_MOUSE_BUTTON4        GLFW_KEY_LAST+9
#define GLFW_MOUSE_BUTTON4_DOUBLE GLFW_KEY_LAST+10
#define GLFW_MOUSE_SCROLL         GLFW_KEY_LAST+11

#define BIND_QUIT              0 // Quit the program
#define BIND_CLOSE_LAST_DIALOG 1 // Closes the last window
#define BIND_CLOSE_ALL_DIALOGS 2 // Closes all windows
#define BIND_NAV_ROTATE        3 // Rotate the camera (navigation)
#define BIND_NAV_TRANSLATE     4 // Camera pan (navigation)
#define BIND_NAV_ZOOM          5 // Camera zoom (navigation)
#define BIND_NAV_RESET         6 // Reset the view (navigation)
#define BIND_MAX               7 // Total number of BIND actions

extern const char *BindNames[BIND_MAX];
extern const int BindGroups[BIND_MAX];

// key binds accessible to other files (to check for scroll)
extern int modbind[BIND_MAX]; // bind -> key
extern int keybind[BIND_MAX]; // bind -> key
extern std::map<std::tuple<int,int,int>,int> keymap; // [key,mod,group] -> bind

void SetDefaultKeyBindings();

void RegisterCallback(int event,void *callback,void *data);

void ProcessCallbacks();

bool IsBindEvent(int bind,bool held);

std::string BindKeyName(int event);

void SetBind(int bind, int key, int mod);

void SetBindEventLevel(int level=0);

bool SetBindFromUserInput(int level);

#endif
