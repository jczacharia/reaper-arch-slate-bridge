// Asks Wine for the pixel format Inf Horizon asks for (window, double-buffered, 24-bit colour,
// 8-bit alpha, 8-bit stencil, multisample) and prints how many formats match. Wine 11's EGL
// backend answers 0 on NVIDIA + Xwayland, the GLX backend answers >= 1. Built with winegcc by
// install/17-opengl-glx.zsh and run inside the prefix to verify the switch took.
#include <windows.h>
#include <GL/gl.h>
#include <stdio.h>
typedef BOOL(WINAPI *PFNCHOOSE)(HDC, const int *, const FLOAT *, UINT, int *, UINT *);
int main(void) {
  WNDCLASSA wc = {0}; wc.lpfnWndProc = DefWindowProcA; wc.hInstance = GetModuleHandleA(0); wc.lpszClassName = "probe"; wc.style = CS_OWNDC;
  RegisterClassA(&wc);
  HWND h = CreateWindowA("probe", "probe", WS_OVERLAPPEDWINDOW, 0, 0, 64, 64, 0, 0, wc.hInstance, 0);
  HDC dc = GetDC(h);
  PIXELFORMATDESCRIPTOR pfd = {sizeof(pfd), 1, PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER, PFD_TYPE_RGBA, 32};
  if (!SetPixelFormat(dc, ChoosePixelFormat(dc, &pfd), &pfd)) { printf("SetPixelFormat failed\n"); return 2; }
  HGLRC rc = wglCreateContext(dc); if (!rc || !wglMakeCurrent(dc, rc)) { printf("no base GL context\n"); return 3; }
  PFNCHOOSE choose = (PFNCHOOSE)wglGetProcAddress("wglChoosePixelFormatARB");
  if (!choose) { printf("wglChoosePixelFormatARB missing\n"); return 4; }
  int attribs[] = {0x2001, 1, 0x2011, 1, 0x2003, 0x2027, 0x2010, 1, 0x2014, 24, 0x201B, 8, 0x2023, 8, 0x2041, 1, 0x2042, 1, 0};
  int pf = 0; UINT n = 0;
  choose(dc, attribs, 0, 1, &pf, &n);
  printf("renderer=%s formats=%u\n", glGetString(GL_RENDERER), n);
  return n ? 0 : 1;
}
