#include <rlang.h>
#include "internal.h"


static bool is_callable(sexp* x) {
  switch (r_typeof(x)) {
  case R_TYPE_symbol:
  case R_TYPE_call:
  case R_TYPE_closure:
  case R_TYPE_builtin:
  case R_TYPE_special:
    return true;
  default:
    return false;
  }
}

sexp* rlang_call2(sexp* fn, sexp* args, sexp* ns) {
  if (r_typeof(fn) == R_TYPE_character) {
    if (r_length(fn) != 1) {
      r_abort("`.fn` must be a string, a symbol, a call, or a function");
    }
    fn = r_sym(r_chr_get_c_string(fn, 0));
  } else if (!is_callable(fn)) {
    r_abort("Can't create call to non-callable object");
  }

  int n_kept = 0;

  if (ns != r_null) {
    if (!r_is_string(ns)) {
      r_abort("`ns` must be a string");
    }
    if (r_typeof(fn) != R_TYPE_symbol) {
      r_abort("`fn` must be a string or symbol when a namespace is supplied");
    }
    ns = r_sym(r_chr_get_c_string(ns, 0));
    fn = KEEP_N(r_call3(r_syms_namespace, ns, fn), &n_kept);
  }

  sexp* out = r_new_call(fn, args);

  FREE(n_kept);
  return out;
}

sexp* rlang_ext2_call2(sexp* call, sexp* op, sexp* args, sexp* env) {
  args = r_node_cdr(args);

  sexp* fn = KEEP(r_eval(r_sym(".fn"), env));
  sexp* ns = KEEP(r_eval(r_sym(".ns"), env));
  sexp* dots = KEEP(rlang_dots(env));

  sexp* out = rlang_call2(fn, dots, ns);

  FREE(3);
  return out;
}
