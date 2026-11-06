// Windows UIA provider（无障碍阶段 3）。
//
// 数据源就一份：stub.c 里的语义快照表（WmA11yRow，字段见 widget/a11y.mbt 的
// TSV 通道）。这里把「窗口 → 根 provider → 快照行」摊成 COM 对象树：
//   - 每个窗口一个根 provider（FragmentRoot），子元素按快照行惰性建；
//   - QueryInterface 只认 IUnknown / IRawElementProviderSimple / Fragment
//     （根另认 FragmentRoot）；
//   - 属性取 id→name、role→ControlType、enabled、BoundingRectangle、
//     AutomationId、IsPassword / IsReadOnly；
//   - Navigate 按快照里的 parent 关系走（FirstChild / Parent / Next / Previous）。
//
// 第二批（五 pattern）：按角色挂 IInvokeProvider（button/link/menuitem）、
// IToggleProvider（checkbox/switch/radio）、IValueProvider（text_input/
// text_area/select）、IRangeValueProvider（slider/stepper/progress）、
// IExpandCollapseProvider（select）；根补 FragmentRoot 接口
// （ElementProviderFromPoint / GetFocus）。
// pattern 的**动作侧**（Invoke/Toggle/Expand）不直接碰组件——Store 与
// Editor 都锁在组件闭包里，C 侧够不着也不该够着——只把「点一下这个控件」
// 压进动作队列，由 MoonBit 侧每帧抽走并合成指针事件（Down+Up 走与真实
// 点击同一条 route_pointer）。Value/RangeValue 的 SetValue 同理不可达：
// 如实回 E_NOTIMPL（读侧照常可用），不装能写。
//
// GUID 取法（方案坑清单第 2 条，本批定案）：C 模式用不了 __uuidof，全部
// IID/PATTERNID 常量由 uiautomationcore.h 声明、链接期从 uiautomationcore.lib
// 取符号——与 WIC 的 windowscodecs.lib、任务栏的 uuid.lib 同一条套路
// （prebuild.py Windows 分支已下发 uiautomationcore.lib / oleaut32.lib）。
//
// 只在 Win32 实现 TU 里编（native-stub 在 Linux/mac 上是空 TU，不能定义符号）；
// 快照访问函数由 stub.c 的同一 TU 定义。
//
// 已知边界（同读侧）：快照表是**进程级单表**（wm_a11y_publish 整体替换），
// 多窗应用里表内是最后绘制那扇窗的树；单窗应用（绝对多数）完全正确。

#if defined(_WIN32)

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>
#include <ole2.h> // VARIANT/BSTR/SysAlloc* 全链（oleauto/oaidl 正序）：裸含 oleauto.h 时 VARIANT 视图不完整
#include <objbase.h> // COM 基础（interface 宏）：uiautomationcore.h 裸用会语法错
#include <uiautomation.h> // 聚合头（UIA_*ControlTypeId / PatternId 常量）
#include <uiautomationclient.h> // UIA_*PropertyId 属性常量（微软文档归属头）
#include <uiautomationcore.h> // provider 接口本体（ToggleState/NavigateDirection/ProviderOptions/UiaRect 的 vtable 签名）
#include <uiautomationcoreapi.h> // UiaReturnRawElementProvider / UiaHostProviderFromHwnd

// stub.c 的快照访问面（同 TU 链接）
typedef struct WmA11yRow {
    int32_t id;
    int32_t parent;
    int32_t enabled;
    char role[32];
    char name[256];
    char state[32];
    char value[64];
    char text[512];
    double x, y, w, h;
} WmA11yRow;

int32_t wm_a11y_count(void);
const WmA11yRow *wm_a11y_row(int32_t i);

typedef struct WmProv {
    IRawElementProviderSimple simple; // vtable 在前（COM 布局）
    IRawElementProviderFragment fragment;
    IRawElementProviderFragmentRoot root; // 仅根 provider（idx<0）认这个接口
    LONG refs;
    HWND hwnd;
    int32_t idx; // 快照行号；-1 = 窗口根
} WmProv;

static WmProv *g_root_prov = NULL;

static WmProv *wm_prov_new(HWND hwnd, int32_t idx);
static IUnknown *wm_inv_new(HWND hwnd, int32_t idx);
static IUnknown *wm_tog_new(HWND hwnd, int32_t idx);
static IUnknown *wm_val_new(HWND hwnd, int32_t idx);
static IUnknown *wm_rng_new(HWND hwnd, int32_t idx);
static IUnknown *wm_exp_new(HWND hwnd, int32_t idx);

/* ---------------- IUnknown ---------------- */

static HRESULT STDMETHODCALLTYPE wm_prov_qi(IUnknown *self, REFIID iid, void **out) {
    WmProv *p = (WmProv *)self;
    if (out == NULL) {
        return E_POINTER;
    }
    *out = NULL;
    if (IsEqualIID(iid, &IID_IUnknown) || IsEqualIID(iid, &IID_IRawElementProviderSimple)) {
        *out = &p->simple;
    } else if (IsEqualIID(iid, &IID_IRawElementProviderFragment)) {
        *out = &p->fragment;
    } else if (p->idx < 0 && IsEqualIID(iid, &IID_IRawElementProviderFragmentRoot)) {
        // FragmentRoot 只有窗口根本尊；子元素认这个接口是客户端问错对象
        *out = &p->root;
    } else {
        return E_NOINTERFACE;
    }
    InterlockedIncrement(&p->refs);
    return S_OK;
}

static ULONG STDMETHODCALLTYPE wm_prov_addref(IUnknown *self) {
    WmProv *p = (WmProv *)self;
    return (ULONG)InterlockedIncrement(&p->refs);
}

static ULONG STDMETHODCALLTYPE wm_prov_release(IUnknown *self) {
    WmProv *p = (WmProv *)self;
    LONG n = InterlockedDecrement(&p->refs);
    if (n == 0) {
        if (g_root_prov == p) {
            g_root_prov = NULL;
        }
        free(p);
    }
    return (ULONG)n;
}

/* ---------------- 读屏动作通道 ----------------
 * pattern 的动作侧只压「(快照行号, 动作)」，MoonBit 侧每帧抽走并合成指针
 * 点击。UIA 调用经 UseComThreading 串行到主线程（进 wndproc），泵也在主
 * 线程，单读者单写者同线程，用普通计数器即可（同 wm_hotkey_fired 口径）。
 * 队列本体在 stub.c 的实现 TU 段（全平台要有符号，GTK/mac 无人压恒空；mac 的
 * NSAccessibility press 动作同压这一份）。动作码宏不跨 TU——两边各写一份
 * （同 WmA11yRow 结构体在两个文件各声明一份的路数）。 */

#define WM_UIA_ACT_CLICK 1

void wm_uia_action_push(int32_t idx, int act);

static void wm_uia_act_click(int32_t idx) {
    wm_uia_action_push(idx, WM_UIA_ACT_CLICK);
}

/* ---------------- 快照 → 属性助手 ---------------- */

static long wm_uia_control_type(const char *role) {
    if (role == NULL || role[0] == 0) return UIA_GroupControlTypeId;
    if (!strcmp(role, "button")) return UIA_ButtonControlTypeId;
    if (!strcmp(role, "checkbox")) return UIA_CheckBoxControlTypeId;
    if (!strcmp(role, "radio")) return UIA_RadioButtonControlTypeId;
    if (!strcmp(role, "switch")) return UIA_CheckBoxControlTypeId;
    if (!strcmp(role, "slider")) return UIA_SliderControlTypeId;
    if (!strcmp(role, "stepper")) return UIA_SpinnerControlTypeId;
    if (!strcmp(role, "text_input")) return UIA_EditControlTypeId;
    if (!strcmp(role, "text_area")) return UIA_DocumentControlTypeId;
    if (!strcmp(role, "select")) return UIA_ComboBoxControlTypeId;
    if (!strcmp(role, "progress")) return UIA_ProgressBarControlTypeId;
    if (!strcmp(role, "text")) return UIA_TextControlTypeId;
    if (!strcmp(role, "heading")) return UIA_TextControlTypeId;
    if (!strcmp(role, "link")) return UIA_HyperlinkControlTypeId;
    if (!strcmp(role, "image")) return UIA_ImageControlTypeId;
    if (!strcmp(role, "tab")) return UIA_TabItemControlTypeId;
    if (!strcmp(role, "menuitem")) return UIA_MenuItemControlTypeId;
    return UIA_GroupControlTypeId;
}

// 快照字段是 UTF-8，BSTR 是 UTF-16：首批的 SysAllocStringByteLen 把 UTF-8
// 字节当 ANSI 直拷，中文名会是乱码——这里统一走 MultiByteToWideChar 转
static void wm_uia_set_bstr(VARIANT *v, const char *s) {
    VariantInit(v);
    v->vt = VT_BSTR;
    if (s == NULL) {
        s = "";
    }
    int wlen = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
    if (wlen > 0) {
        BSTR b = SysAllocStringLen(NULL, (UINT)(wlen - 1));
        if (b != NULL) {
            MultiByteToWideChar(CP_UTF8, 0, s, -1, b, wlen);
            v->bstrVal = b;
            return;
        }
    }
    v->bstrVal = SysAllocStringW(L"");
}

// 角色是否落在给定集合里（pattern 挂载判据）
static int wm_role_in(const char *role, const char *a, const char *b, const char *c) {
    return role != NULL &&
        ((a != NULL && !strcmp(role, a)) || (b != NULL && !strcmp(role, b)) ||
         (c != NULL && !strcmp(role, c)));
}

// "50%" → 50.0（RangeValue 的百分比口径：快照值就是范围百分比）
static double wm_uia_pct(const char *s) {
    if (s == NULL) {
        return 0.0;
    }
    double v = 0.0;
    int seen = 0;
    for (const char *q = s; *q != 0; q++) {
        if (*q >= '0' && *q <= '9') {
            v = v * 10.0 + (double)(*q - '0');
            seen = 1;
        } else if (*q == '.' || *q == ' ') {
            continue;
        } else if (seen) {
            break;
        }
    }
    return v;
}

/* ---------------- 五 pattern provider ----------------
 * 形态与 IDropTarget 同款：对象只持 (hwnd, 快照行号)，vtable 共享静态表，
 * 值读侧从快照现取，动作侧压队列。 */

typedef struct WmInv {
    IInvokeProvider inv; // 主接口在前，兼作 IUnknown（QI 对两者都回它）
    LONG refs;
    HWND hwnd;
    int32_t idx;
} WmInv;

static HRESULT STDMETHODCALLTYPE wm_inv_qi(IUnknown *self, REFIID iid, void **out) {
    WmInv *p = (WmInv *)self;
    if (out == NULL) return E_POINTER;
    *out = NULL;
    if (IsEqualIID(iid, &IID_IUnknown) || IsEqualIID(iid, &IID_IInvokeProvider)) {
        *out = &p->inv;
    } else {
        return E_NOINTERFACE;
    }
    InterlockedIncrement(&p->refs);
    return S_OK;
}

static ULONG STDMETHODCALLTYPE wm_inv_addref(IUnknown *self) {
    return (ULONG)InterlockedIncrement(&((WmInv *)self)->refs);
}

static ULONG STDMETHODCALLTYPE wm_inv_release(IUnknown *self) {
    WmInv *p = (WmInv *)self;
    LONG n = InterlockedDecrement(&p->refs);
    if (n == 0) free(p);
    return (ULONG)n;
}

// Invoke = 点一下：合成点击走 MoonBit 侧（见 wm_uia_action_push 注）
static HRESULT STDMETHODCALLTYPE wm_inv_invoke(IInvokeProvider *self) {
    WmInv *p = (WmInv *)self;
    wm_uia_act_click(p->idx);
    return S_OK;
}

static IInvokeProviderVtbl g_inv_vtbl = {
    (void *)wm_inv_qi, (void *)wm_inv_addref, (void *)wm_inv_release,
    (void *)wm_inv_invoke,
};

static IUnknown *wm_inv_new(HWND hwnd, int32_t idx) {
    WmInv *p = (WmInv *)calloc(1, sizeof(WmInv));
    if (p == NULL) return NULL;
    p->inv.lpVtbl = &g_inv_vtbl;
    p->refs = 1;
    p->hwnd = hwnd;
    p->idx = idx;
    return (IUnknown *)&p->inv;
}

typedef struct WmTog {
    IToggleProvider tog; // 主接口在前，兼作 IUnknown
    LONG refs;
    HWND hwnd;
    int32_t idx;
} WmTog;

static HRESULT STDMETHODCALLTYPE wm_tog_qi(IUnknown *self, REFIID iid, void **out) {
    WmTog *p = (WmTog *)self;
    if (out == NULL) return E_POINTER;
    *out = NULL;
    if (IsEqualIID(iid, &IID_IUnknown) || IsEqualIID(iid, &IID_IToggleProvider)) {
        *out = &p->tog;
    } else {
        return E_NOINTERFACE;
    }
    InterlockedIncrement(&p->refs);
    return S_OK;
}

static ULONG STDMETHODCALLTYPE wm_tog_addref(IUnknown *self) {
    return (ULONG)InterlockedIncrement(&((WmTog *)self)->refs);
}

static ULONG STDMETHODCALLTYPE wm_tog_release(IUnknown *self) {
    WmTog *p = (WmTog *)self;
    LONG n = InterlockedDecrement(&p->refs);
    if (n == 0) free(p);
    return (ULONG)n;
}

static HRESULT STDMETHODCALLTYPE wm_tog_toggle(IToggleProvider *self) {
    WmTog *p = (WmTog *)self;
    wm_uia_act_click(p->idx);
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE wm_tog_state(IToggleProvider *self, ToggleState *ret) {
    WmTog *p = (WmTog *)self;
    if (ret == NULL) return E_POINTER;
    const WmA11yRow *r = wm_a11y_row(p->idx);
    // 快照 state 串：checked / unchecked（其余按未勾选）
    *ret = (r != NULL && !strcmp(r->state, "checked")) ? ToggleState_On : ToggleState_Off;
    return S_OK;
}

static IToggleProviderVtbl g_tog_vtbl = {
    (void *)wm_tog_qi, (void *)wm_tog_addref, (void *)wm_tog_release,
    (void *)wm_tog_toggle, (void *)wm_tog_state,
};

static IUnknown *wm_tog_new(HWND hwnd, int32_t idx) {
    WmTog *p = (WmTog *)calloc(1, sizeof(WmTog));
    if (p == NULL) return NULL;
    p->tog.lpVtbl = &g_tog_vtbl;
    p->refs = 1;
    p->hwnd = hwnd;
    p->idx = idx;
    return (IUnknown *)&p->tog;
}

typedef struct WmVal {
    IValueProvider val; // 主接口在前，兼作 IUnknown
    LONG refs;
    HWND hwnd;
    int32_t idx;
} WmVal;

static HRESULT STDMETHODCALLTYPE wm_val_qi(IUnknown *self, REFIID iid, void **out) {
    WmVal *p = (WmVal *)self;
    if (out == NULL) return E_POINTER;
    *out = NULL;
    if (IsEqualIID(iid, &IID_IUnknown) || IsEqualIID(iid, &IID_IValueProvider)) {
        *out = &p->val;
    } else {
        return E_NOINTERFACE;
    }
    InterlockedIncrement(&p->refs);
    return S_OK;
}

static ULONG STDMETHODCALLTYPE wm_val_addref(IUnknown *self) {
    return (ULONG)InterlockedIncrement(&((WmVal *)self)->refs);
}

static ULONG STDMETHODCALLTYPE wm_val_release(IUnknown *self) {
    WmVal *p = (WmVal *)self;
    LONG n = InterlockedDecrement(&p->refs);
    if (n == 0) free(p);
    return (ULONG)n;
}

// 文本在组件闭包的 Editor 里，桥不直写也不该直写：如实报「未实现」，
// 读侧（get_Value）照常可用——不装能写
static HRESULT STDMETHODCALLTYPE wm_val_setvalue(IValueProvider *self, LPCWSTR val) {
    (void)self;
    (void)val;
    return E_NOTIMPL;
}

static HRESULT STDMETHODCALLTYPE wm_val_getvalue(IValueProvider *self, BSTR *ret) {
    WmVal *p = (WmVal *)self;
    if (ret == NULL) return E_POINTER;
    const WmA11yRow *r = wm_a11y_row(p->idx);
    const char *v = "";
    if (r != NULL) {
        if (!strcmp(r->state, "password")) {
            v = ""; // 密码框 value 绝不出明文（与 IsPassword 属性同源）
        } else if (r->value[0] != 0) {
            v = r->value; // select 的当前值
        } else {
            v = r->text; // 输入框/多行文本
        }
    }
    VARIANT var;
    wm_uia_set_bstr(&var, v);
    *ret = var.bstrVal;
    return S_OK;
}

static IValueProviderVtbl g_val_vtbl = {
    (void *)wm_val_qi, (void *)wm_val_addref, (void *)wm_val_release,
    (void *)wm_val_setvalue, (void *)wm_val_getvalue,
};

static IUnknown *wm_val_new(HWND hwnd, int32_t idx) {
    WmVal *p = (WmVal *)calloc(1, sizeof(WmVal));
    if (p == NULL) return NULL;
    p->val.lpVtbl = &g_val_vtbl;
    p->refs = 1;
    p->hwnd = hwnd;
    p->idx = idx;
    return (IUnknown *)&p->val;
}

typedef struct WmRng {
    IRangeValueProvider rng; // 主接口在前，兼作 IUnknown
    LONG refs;
    HWND hwnd;
    int32_t idx;
} WmRng;

static HRESULT STDMETHODCALLTYPE wm_rng_qi(IUnknown *self, REFIID iid, void **out) {
    WmRng *p = (WmRng *)self;
    if (out == NULL) return E_POINTER;
    *out = NULL;
    if (IsEqualIID(iid, &IID_IUnknown) || IsEqualIID(iid, &IID_IRangeValueProvider)) {
        *out = &p->rng;
    } else {
        return E_NOINTERFACE;
    }
    InterlockedIncrement(&p->refs);
    return S_OK;
}

static ULONG STDMETHODCALLTYPE wm_rng_addref(IUnknown *self) {
    return (ULONG)InterlockedIncrement(&((WmRng *)self)->refs);
}

static ULONG STDMETHODCALLTYPE wm_rng_release(IUnknown *self) {
    WmRng *p = (WmRng *)self;
    LONG n = InterlockedDecrement(&p->refs);
    if (n == 0) free(p);
    return (ULONG)n;
}

// 值在组件 Store 里，桥不直写：如实报「未实现」（键盘/指针是正道）
static HRESULT STDMETHODCALLTYPE wm_rng_setvalue(IRangeValueProvider *self, double val) {
    (void)self;
    (void)val;
    return E_NOTIMPL;
}

static HRESULT STDMETHODCALLTYPE wm_rng_value(IRangeValueProvider *self, double *ret) {
    WmRng *p = (WmRng *)self;
    if (ret == NULL) return E_POINTER;
    const WmA11yRow *r = wm_a11y_row(p->idx);
    *ret = r != NULL ? wm_uia_pct(r->value) : 0.0;
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE wm_rng_readonly(IRangeValueProvider *self, BOOL *ret) {
    WmRng *p = (WmRng *)self;
    if (ret == NULL) return E_POINTER;
    const WmA11yRow *r = wm_a11y_row(p->idx);
    // 禁用态控件对读屏是只读（disabled 恒 true 的行）
    *ret = (r != NULL && !r->enabled) ? TRUE : FALSE;
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE wm_rng_max(IRangeValueProvider *self, double *ret) {
    (void)self;
    if (ret == NULL) return E_POINTER;
    *ret = 100.0; // 快照值是范围百分比，口径 0–100
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE wm_rng_min(IRangeValueProvider *self, double *ret) {
    (void)self;
    if (ret == NULL) return E_POINTER;
    *ret = 0.0;
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE wm_rng_large(IRangeValueProvider *self, double *ret) {
    (void)self;
    if (ret == NULL) return E_POINTER;
    *ret = 10.0;
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE wm_rng_small(IRangeValueProvider *self, double *ret) {
    (void)self;
    if (ret == NULL) return E_POINTER;
    *ret = 1.0;
    return S_OK;
}

static IRangeValueProviderVtbl g_rng_vtbl = {
    (void *)wm_rng_qi, (void *)wm_rng_addref, (void *)wm_rng_release,
    (void *)wm_rng_setvalue, (void *)wm_rng_value, (void *)wm_rng_readonly,
    (void *)wm_rng_max, (void *)wm_rng_min, (void *)wm_rng_large,
    (void *)wm_rng_small,
};

static IUnknown *wm_rng_new(HWND hwnd, int32_t idx) {
    WmRng *p = (WmRng *)calloc(1, sizeof(WmRng));
    if (p == NULL) return NULL;
    p->rng.lpVtbl = &g_rng_vtbl;
    p->refs = 1;
    p->hwnd = hwnd;
    p->idx = idx;
    return (IUnknown *)&p->rng;
}

typedef struct WmExp {
    IExpandCollapseProvider exp; // 主接口在前，兼作 IUnknown
    LONG refs;
    HWND hwnd;
    int32_t idx;
} WmExp;

static HRESULT STDMETHODCALLTYPE wm_exp_qi(IUnknown *self, REFIID iid, void **out) {
    WmExp *p = (WmExp *)self;
    if (out == NULL) return E_POINTER;
    *out = NULL;
    if (IsEqualIID(iid, &IID_IUnknown) || IsEqualIID(iid, &IID_IExpandCollapseProvider)) {
        *out = &p->exp;
    } else {
        return E_NOINTERFACE;
    }
    InterlockedIncrement(&p->refs);
    return S_OK;
}

static ULONG STDMETHODCALLTYPE wm_exp_addref(IUnknown *self) {
    return (ULONG)InterlockedIncrement(&((WmExp *)self)->refs);
}

static ULONG STDMETHODCALLTYPE wm_exp_release(IUnknown *self) {
    WmExp *p = (WmExp *)self;
    LONG n = InterlockedDecrement(&p->refs);
    if (n == 0) free(p);
    return (ULONG)n;
}

// 展开 = 点一下弹出候选层
static HRESULT STDMETHODCALLTYPE wm_exp_expand(IExpandCollapseProvider *self) {
    WmExp *p = (WmExp *)self;
    wm_uia_act_click(p->idx);
    return S_OK;
}

// 收起：状态恒报 Collapsed（快照没有展开态，弹出层是独立窗），已收起时
// 收起是空操作——不补点击（补了会反而弹开）
static HRESULT STDMETHODCALLTYPE wm_exp_collapse(IExpandCollapseProvider *self) {
    (void)self;
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE wm_exp_state(IExpandCollapseProvider *self,
                                              ExpandCollapseState *ret) {
    (void)self;
    if (ret == NULL) return E_POINTER;
    *ret = ExpandCollapseState_Collapsed;
    return S_OK;
}

static IExpandCollapseProviderVtbl g_exp_vtbl = {
    (void *)wm_exp_qi, (void *)wm_exp_addref, (void *)wm_exp_release,
    (void *)wm_exp_collapse, (void *)wm_exp_expand, (void *)wm_exp_state,
};

static IUnknown *wm_exp_new(HWND hwnd, int32_t idx) {
    WmExp *p = (WmExp *)calloc(1, sizeof(WmExp));
    if (p == NULL) return NULL;
    p->exp.lpVtbl = &g_exp_vtbl;
    p->refs = 1;
    p->hwnd = hwnd;
    p->idx = idx;
    return (IUnknown *)&p->exp;
}

/* ---------------- IRawElementProviderSimple ---------------- */

static HRESULT STDMETHODCALLTYPE wm_prov_options(IRawElementProviderSimple *self,
                                                 ProviderOptions *ret) {
    (void)self;
    if (ret == NULL) return E_POINTER;
    *ret = ProviderOptions_ServerSideProvider | ProviderOptions_UseComThreading;
    return S_OK;
}

// 按角色挂 pattern（见文件头第二批说明）
static HRESULT STDMETHODCALLTYPE wm_prov_pattern(IRawElementProviderSimple *self,
                                                 PATTERNID id, IUnknown **ret) {
    WmProv *p = (WmProv *)self;
    if (ret == NULL) return E_POINTER;
    *ret = NULL;
    if (p->idx < 0) {
        return S_OK; // 窗口根不给 pattern
    }
    const WmA11yRow *r = wm_a11y_row(p->idx);
    if (r == NULL) {
        return S_OK;
    }
    const char *role = r->role;
    if (id == UIA_InvokePatternId && wm_role_in(role, "button", "link", "menuitem")) {
        *ret = wm_inv_new(p->hwnd, p->idx);
    } else if (id == UIA_TogglePatternId && wm_role_in(role, "checkbox", "switch", "radio")) {
        *ret = wm_tog_new(p->hwnd, p->idx);
    } else if (id == UIA_ValuePatternId && wm_role_in(role, "text_input", "text_area", "select")) {
        *ret = wm_val_new(p->hwnd, p->idx);
    } else if (id == UIA_RangeValuePatternId && wm_role_in(role, "slider", "stepper", "progress")) {
        *ret = wm_rng_new(p->hwnd, p->idx);
    } else if (id == UIA_ExpandCollapsePatternId && !strcmp(role, "select")) {
        *ret = wm_exp_new(p->hwnd, p->idx);
    }
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE wm_prov_prop(IRawElementProviderSimple *self,
                                              PROPERTYID id, VARIANT *ret) {
    WmProv *p = (WmProv *)self;
    if (ret == NULL) return E_POINTER;
    VariantInit(ret);
    const WmA11yRow *r = p->idx >= 0 ? wm_a11y_row(p->idx) : NULL;
    switch (id) {
        case UIA_NamePropertyId:
            wm_uia_set_bstr(ret, r != NULL ? r->name : "window");
            return S_OK;
        case UIA_AutomationIdPropertyId:
            if (r != NULL) {
                char buf[32];
                snprintf(buf, sizeof buf, "w%d", (int)r->id);
                wm_uia_set_bstr(ret, buf);
            } else {
                wm_uia_set_bstr(ret, "window");
            }
            return S_OK;
        case UIA_ControlTypePropertyId:
            ret->vt = VT_I4;
            ret->lVal = r != NULL ? wm_uia_control_type(r->role) : UIA_WindowControlTypeId;
            return S_OK;
        case UIA_IsEnabledPropertyId:
            ret->vt = VT_BOOL;
            ret->boolVal = (r == NULL || r->enabled) ? VARIANT_TRUE : VARIANT_FALSE;
            return S_OK;
        case UIA_IsControlElementPropertyId:
        case UIA_IsContentElementPropertyId:
        case UIA_IsKeyboardFocusablePropertyId:
            ret->vt = VT_BOOL;
            ret->boolVal = VARIANT_TRUE;
            return S_OK;
        case UIA_IsPasswordPropertyId:
            // 密码框：读屏侧据此时不朗读圆点后的明文
            ret->vt = VT_BOOL;
            ret->boolVal = (r != NULL && !strcmp(r->state, "password")) ? VARIANT_TRUE
                                                                        : VARIANT_FALSE;
            return S_OK;
        case UIA_IsReadOnlyPropertyId:
            ret->vt = VT_BOOL;
            ret->boolVal = (r != NULL && !strcmp(r->state, "read_only")) ? VARIANT_TRUE
                                                                         : VARIANT_FALSE;
            return S_OK;
        case UIA_HelpTextPropertyId:
            wm_uia_set_bstr(ret, r != NULL ? r->state : "");
            return S_OK;
        default:
            return S_OK; // 空 VARIANT = 不支持该属性
    }
}

static HRESULT STDMETHODCALLTYPE wm_prov_host(IRawElementProviderSimple *self,
                                              IRawElementProviderSimple **ret) {
    WmProv *p = (WmProv *)self;
    if (ret == NULL) return E_POINTER;
    return UiaHostProviderFromHwnd(p->hwnd, ret);
}

/* ---------------- IRawElementProviderFragment ---------------- */

// 找 idx 行的第一个子元素在快照里的下标；没有返回 -1
static int32_t wm_uia_child_of(int32_t idx, int32_t skip) {
    int32_t n = wm_a11y_count();
    int32_t seen = 0;
    for (int32_t i = 0; i < n; i++) {
        const WmA11yRow *r = wm_a11y_row(i);
        if (r != NULL && r->parent == idx) {
            if (seen == skip) return i;
            seen++;
        }
    }
    return -1;
}

// 快照里包含 (wx, wy) 的最深一行（前序展开，后行更深）；没有返回 -1
static int32_t wm_uia_deepest_at(double wx, double wy) {
    int32_t best = -1;
    int32_t n = wm_a11y_count();
    for (int32_t i = 0; i < n; i++) {
        const WmA11yRow *r = wm_a11y_row(i);
        if (r == NULL) continue;
        if (wx >= r->x && wx <= r->x + r->w && wy >= r->y && wy <= r->y + r->h) {
            best = i;
        }
    }
    return best;
}

static HRESULT STDMETHODCALLTYPE wm_prov_navigate(IRawElementProviderFragment *self,
                                                  NavigateDirection dir,
                                                  IRawElementProviderSimple **ret) {
    WmProv *p = (WmProv *)self;
    if (ret == NULL) return E_POINTER;
    *ret = NULL;
    if (p->idx < 0) {
        if (dir == NavigateDirection_FirstChild) {
            int32_t c = wm_uia_child_of(0, 0);
            if (c >= 0) *ret = &wm_prov_new(p->hwnd, c)->simple;
        }
        return S_OK;
    }
    const WmA11yRow *r = wm_a11y_row(p->idx);
    if (r == NULL) return S_OK;
    switch (dir) {
        case NavigateDirection_Parent: {
            if (r->parent == 0) {
                if (g_root_prov != NULL) *ret = &g_root_prov->simple;
            } else {
                int32_t n = wm_a11y_count();
                for (int32_t i = 0; i < n; i++) {
                    const WmA11yRow *q = wm_a11y_row(i);
                    if (q != NULL && q->id == r->parent) {
                        *ret = &wm_prov_new(p->hwnd, i)->simple;
                        break;
                    }
                }
            }
            break;
        }
        case NavigateDirection_FirstChild: {
            int32_t c = wm_uia_child_of(r->id, 0);
            if (c >= 0) *ret = &wm_prov_new(p->hwnd, c)->simple;
            break;
        }
        case NavigateDirection_NextSibling:
        case NavigateDirection_PreviousSibling: {
            int32_t n = wm_a11y_count();
            int32_t step = dir == NavigateDirection_NextSibling ? 1 : -1;
            for (int32_t i = p->idx + step; i >= 0 && i < n; i += step) {
                const WmA11yRow *q = wm_a11y_row(i);
                if (q != NULL && q->parent == r->parent) {
                    *ret = &wm_prov_new(p->hwnd, i)->simple;
                    break;
                }
            }
            break;
        }
        default:
            break;
    }
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE wm_prov_runtime_id(IRawElementProviderFragment *self,
                                                    SAFEARRAY **ret) {
    WmProv *p = (WmProv *)self;
    if (ret == NULL) return E_POINTER;
    int v[2];
    v[0] = (int)(intptr_t)p->hwnd;
    v[1] = p->idx + 1;
    return UiaCreateRuntimeId(v, 2, ret);
}

static HRESULT STDMETHODCALLTYPE wm_prov_rect(IRawElementProviderFragment *self,
                                              UiaRect *ret) {
    WmProv *p = (WmProv *)self;
    if (ret == NULL) return E_POINTER;
    memset(ret, 0, sizeof *ret);
    RECT rc;
    if (GetWindowRect(p->hwnd, &rc) == 0) return S_OK;
    if (p->idx < 0) {
        // 窗口根：整窗客户区（物理像素，UIA 也要物理像素）
        RECT cr;
        GetClientRect(p->hwnd, &cr);
        POINT tl = {cr.left, cr.top};
        ClientToScreen(p->hwnd, &tl);
        ret->left = tl.x;
        ret->top = tl.y;
        ret->width = cr.right - cr.left;
        ret->height = cr.bottom - cr.top;
        return S_OK;
    }
    const WmA11yRow *r = wm_a11y_row(p->idx);
    if (r != NULL) {
        ret->left = rc.left + r->x;
        ret->top = rc.top + r->y;
        ret->width = r->w;
        ret->height = r->h;
    }
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE wm_prov_embedded(IRawElementProviderFragment *self,
                                                  SAFEARRAY **ret) {
    (void)self;
    if (ret != NULL) *ret = NULL;
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE wm_prov_focus(IRawElementProviderFragment *self) {
    WmProv *p = (WmProv *)self;
    SetForegroundWindow(p->hwnd);
    SetFocus(p->hwnd);
    return S_OK;
}

// 根自己就是 FragmentRoot；子元素回窗根（问错对象的客户端拿 NULL）
static HRESULT STDMETHODCALLTYPE wm_prov_fragment_root(IRawElementProviderFragment *self,
                                                       IRawElementProviderFragmentRoot **ret) {
    WmProv *p = (WmProv *)self;
    if (ret == NULL) return E_POINTER;
    if (p->idx < 0) {
        *ret = &p->root;
        InterlockedIncrement(&p->refs);
    } else if (g_root_prov != NULL && g_root_prov->hwnd == p->hwnd) {
        *ret = &g_root_prov->root;
        InterlockedIncrement(&g_root_prov->refs);
    } else {
        *ret = NULL;
    }
    return S_OK;
}

/* ---------------- IRawElementProviderFragmentRoot ---------------- */

// 屏幕坐标 → 快照最深行（读屏「这个点上有什么」）
static HRESULT STDMETHODCALLTYPE wm_prov_from_point(IRawElementProviderFragmentRoot *self,
                                                    double x, double y,
                                                    IRawElementProviderSimple **ret) {
    WmProv *p = (WmProv *)self;
    if (ret == NULL) return E_POINTER;
    *ret = NULL;
    RECT rc;
    if (GetWindowRect(p->hwnd, &rc) == 0) return S_OK;
    int32_t i = wm_uia_deepest_at(x - rc.left, y - rc.top);
    if (i >= 0) *ret = &wm_prov_new(p->hwnd, i)->simple;
    return S_OK;
}

// 焦点元素：快照没有焦点字段（一期不做，见方案），回窗根（UIA 视作窗口级
// 焦点）；不报「无焦点」是怕客户端据此判定整窗不可交互
static HRESULT STDMETHODCALLTYPE wm_prov_get_focus(IRawElementProviderFragmentRoot *self,
                                                   IRawElementProviderSimple **ret) {
    WmProv *p = (WmProv *)self;
    if (ret == NULL) return E_POINTER;
    if (g_root_prov != NULL && g_root_prov->hwnd == p->hwnd) {
        *ret = &g_root_prov->simple;
        InterlockedIncrement(&g_root_prov->refs);
    } else {
        *ret = &p->simple;
        InterlockedIncrement(&p->refs);
    }
    return S_OK;
}

static IRawElementProviderSimpleVtbl g_simple_vtbl = {
    (void *)wm_prov_qi, (void *)wm_prov_addref, (void *)wm_prov_release,
    (void *)wm_prov_options, (void *)wm_prov_pattern, (void *)wm_prov_prop,
    (void *)wm_prov_host,
};

static IRawElementProviderFragmentVtbl g_frag_vtbl = {
    (void *)wm_prov_qi, (void *)wm_prov_addref, (void *)wm_prov_release,
    (void *)wm_prov_options, (void *)wm_prov_pattern, (void *)wm_prov_prop,
    (void *)wm_prov_host,
    (void *)wm_prov_navigate, (void *)wm_prov_runtime_id, (void *)wm_prov_rect,
    (void *)wm_prov_embedded, (void *)wm_prov_focus, (void *)wm_prov_fragment_root,
};

// FragmentRoot = fragment 的 13 项 + ElementProviderFromPoint + GetFocus
static IRawElementProviderFragmentRootVtbl g_root_vtbl = {
    (void *)wm_prov_qi, (void *)wm_prov_addref, (void *)wm_prov_release,
    (void *)wm_prov_options, (void *)wm_prov_pattern, (void *)wm_prov_prop,
    (void *)wm_prov_host,
    (void *)wm_prov_navigate, (void *)wm_prov_runtime_id, (void *)wm_prov_rect,
    (void *)wm_prov_embedded, (void *)wm_prov_focus, (void *)wm_prov_fragment_root,
    (void *)wm_prov_from_point, (void *)wm_prov_get_focus,
};

static WmProv *wm_prov_new(HWND hwnd, int32_t idx) {
    WmProv *p = (WmProv *)calloc(1, sizeof(WmProv));
    if (p == NULL) return NULL;
    p->simple.lpVtbl = &g_simple_vtbl;
    p->fragment.lpVtbl = &g_frag_vtbl;
    p->root.lpVtbl = &g_root_vtbl;
    p->refs = 1;
    p->hwnd = hwnd;
    p->idx = idx;
    return p;
}

/* WM_GETOBJECT 的入口：返回根 provider（窗口级），子元素由 Navigate 惰性展开 */
LRESULT wm_uia_get_object(HWND hwnd, WPARAM wp, LPARAM lp) {
    if (g_root_prov == NULL || g_root_prov->hwnd != hwnd) {
        if (g_root_prov != NULL) {
            IRawElementProviderSimple *old = &g_root_prov->simple;
            wm_prov_release((IUnknown *)old);
        }
        g_root_prov = wm_prov_new(hwnd, -1);
    }
    return UiaReturnRawElementProvider(hwnd, wp, lp, &g_root_prov->simple);
}

#else

// 非 Windows：空 TU（native-stub 在 Linux/mac 上编这一份，不能定义符号）
typedef int wm_uia_unused;

#endif
