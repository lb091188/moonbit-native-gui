// Windows UIA provider（无障碍阶段 3）。
//
// 数据源就一份：stub.c 里的语义快照表（WmA11yRow，字段见 widget/a11y.mbt 的
// TSV 通道）。这里把「窗口 → 根 provider → 快照行」摊成 COM 对象树：
//   - 每个窗口一个根 provider（FragmentRoot），子元素按快照行惰性建；
//   - QueryInterface 只认 IUnknown / IRawElementProviderSimple / Fragment；
//   - 属性取 id→name、role→ControlType、enabled、BoundingRectangle、AutomationId；
//   - Navigate 按快照里的 parent 关系走（FirstChild / Parent / Next / Previous）。
// 首批不给 pattern（Invoke / RangeValue 下一批），GetPatternProvider 一律 NULL。
//
// 只在 Win32 实现 TU 里编（native-stub 在 Linux/mac 上是空 TU，不能定义符号）；
// 快照访问函数由 stub.c 的同一 TU 定义。

#if defined(_WIN32)

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>
#include <oleauto.h>
#include <uiautomationcore.h>
#include <uiautomationcoreapi.h>

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
    LONG refs;
    HWND hwnd;
    int32_t idx;   // 快照行号；-1 = 窗口根
} WmProv;

static WmProv *g_root_prov = NULL;

static WmProv *wm_prov_new(HWND hwnd, int32_t idx);

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

/* ---------------- 快照 → 属性 ---------------- */

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

static void wm_uia_set_bstr(VARIANT *v, const char *s) {
    VariantInit(v);
    v->vt = VT_BSTR;
    v->bstrVal = SysAllocStringByteLen(s != NULL ? s : "", (UINT)strlen(s != NULL ? s : ""));
}

/* ---------------- IRawElementProviderSimple ---------------- */

static HRESULT STDMETHODCALLTYPE wm_prov_options(IRawElementProviderSimple *self,
                                                 ProviderOptions *ret) {
    (void)self;
    if (ret == NULL) return E_POINTER;
    *ret = ProviderOptions_ServerSideProvider | ProviderOptions_UseComThreading;
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE wm_prov_pattern(IRawElementProviderSimple *self,
                                                 PATTERNID id, IUnknown **ret) {
    (void)self;
    (void)id;
    if (ret == NULL) return E_POINTER;
    *ret = NULL; // 首批不给 pattern
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

static HRESULT STDMETHODCALLTYPE wm_prov_fragment_root(IRawElementProviderFragment *self,
                                                       IRawElementProviderFragmentRoot **ret) {
    (void)self;
    if (ret == NULL) return E_POINTER;
    *ret = NULL; // 根自己就是 FragmentRoot，下一批补齐接口
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

static WmProv *wm_prov_new(HWND hwnd, int32_t idx) {
    WmProv *p = (WmProv *)calloc(1, sizeof(WmProv));
    if (p == NULL) return NULL;
    p->simple.lpVtbl = &g_simple_vtbl;
    p->fragment.lpVtbl = &g_frag_vtbl;
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
