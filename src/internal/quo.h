#ifndef RLANG_INTERNAL_QUO_H
#define RLANG_INTERNAL_QUO_H


r_obj* rlang_new_quosure(r_obj* expr, r_obj* env);
bool rlang_is_quosure(r_obj* x);

r_obj* rlang_get_expression(r_obj* x, r_obj* alternate);

r_obj* rlang_quo_get_env(r_obj* quo);
r_obj* rlang_quo_get_expr(r_obj* quo);

static inline r_obj* rlang_quo_get_expr_(r_obj* quo) {
  return r_node_cadr(quo);
}

void check_quosure(r_obj* x);
bool quo_is_missing(r_obj* quo);
bool quo_is_symbol(r_obj* quo);
bool quo_is_call(r_obj* quo);
bool quo_is_symbolic(r_obj* quo);
bool quo_is_null(r_obj* quo);


#endif
