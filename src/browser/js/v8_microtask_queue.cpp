#ifdef __APPLE__
#define LP_V8_SYMBOL(name) "_" name
#else
#define LP_V8_SYMBOL(name) name
#endif

extern "C" bool lp_v8_Isolate_InContext(void*)
    asm(LP_V8_SYMBOL("_ZN2v87Isolate9InContextEv"));
extern "C" void lp_v8_Context_SetMicrotaskQueue(void*, void*)
    asm(LP_V8_SYMBOL("_ZN2v87Context17SetMicrotaskQueueEPNS_14MicrotaskQueueE"));

extern "C" bool lp_v8__Isolate__CanSetMicrotaskQueue(void* isolate) {
    return !lp_v8_Isolate_InContext(isolate);
}

extern "C" void lp_v8__Context__SetMicrotaskQueue(
    void* context,
    void* queue
) {
    lp_v8_Context_SetMicrotaskQueue(context, queue);
}
