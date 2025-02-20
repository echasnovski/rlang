#include <rlang.h>


static
bool has_correct_length(r_obj* x, r_ssize n) {
  return n < 0 || r_length(x) == n;
}

bool r_is_atomic(r_obj* x, r_ssize n) {
  switch(r_typeof(x)) {
  case R_TYPE_logical:
  case R_TYPE_integer:
  case R_TYPE_double:
  case R_TYPE_complex:
  case R_TYPE_character:
  case RAWSXP:
    return has_correct_length(x, n);
  default:
    return false;
  }
}

bool r_is_vector(r_obj* x, r_ssize n) {
  switch(r_typeof(x)) {
  case R_TYPE_logical:
  case R_TYPE_integer:
  case R_TYPE_double:
  case R_TYPE_complex:
  case R_TYPE_character:
  case RAWSXP:
  case VECSXP:
    return has_correct_length(x, n);
  default:
    return false;
  }
}

bool r_is_logical(r_obj* x, r_ssize n) {
  return r_typeof(x) == R_TYPE_logical && has_correct_length(x, n);
}

bool r_is_finite(r_obj* x) {
  r_ssize n = r_length(x);

  switch(r_typeof(x)) {
  case R_TYPE_integer: {
    const int* p_x = r_int_cbegin(x);
    for (r_ssize i = 0; i < n; ++i) {
      if (p_x[i] == r_globals.na_int) {
        return false;
      }
    }
    break;
  }
  case R_TYPE_double: {
    const double* p_x = r_dbl_cbegin(x);
    for (r_ssize i = 0; i < n; ++i) {
      if (!isfinite(p_x[i])) {
        return false;
      }
    }
    break;
  }
  case R_TYPE_complex: {
    const r_complex_t* p_x = r_cpl_cbegin(x);
    for (r_ssize i = 0; i < n; ++i) {
      if (!isfinite(p_x[i].r) || !isfinite(p_x[i].i)) {
        return false;
      }
    }
    break;
  }
  default:
    r_abort("Internal error: expected a numeric vector");
  }

  return true;
}
bool r_is_integer(r_obj* x, r_ssize n, int finite) {
  if (r_typeof(x) != R_TYPE_integer || !has_correct_length(x, n)) {
    return false;
  }
  if (finite >= 0 && (bool) finite != r_is_finite(x)) {
    return false;
  }
  return true;
}
bool r_is_double(r_obj* x, r_ssize n, int finite) {
  if (r_typeof(x) != R_TYPE_double || !has_correct_length(x, n)) {
    return false;
  }
  if (finite >= 0 && (bool) finite != r_is_finite(x)) {
    return false;
  }
  return true;
}
bool r_is_complex(r_obj* x, r_ssize n, int finite) {
  if (r_typeof(x) != R_TYPE_complex || !has_correct_length(x, n)) {
    return false;
  }
  if (finite >= 0 && (bool) finite != r_is_finite(x)) {
    return false;
  }
  return true;
}

// Allow integers up to 2^52, same as R_XLEN_T_MAX when long vector
// support is enabled
#define RLANG_MAX_DOUBLE_INT 4503599627370496

bool r_is_integerish(r_obj* x, r_ssize n, int finite) {
  if (r_typeof(x) == R_TYPE_integer) {
    return r_is_integer(x, n, finite);
  }
  if (r_typeof(x) != R_TYPE_double || !has_correct_length(x, n)) {
    return false;
  }

  r_ssize actual_n = r_length(x);
  const double* p_x = r_dbl_cbegin(x);
  bool actual_finite = true;

  for (r_ssize i = 0; i < actual_n; ++i) {
    double elt = p_x[i];

    if (!isfinite(elt)) {
      actual_finite = false;
      continue;
    }

    if (elt > RLANG_MAX_DOUBLE_INT) {
      return false;
    }

    // C99 guarantees existence of the int_least_N_t types, even on
    // machines that don't support arithmetic on width N:
    if (elt != (int_least64_t) elt) {
      return false;
    }
  }

  if (finite >= 0 && actual_finite != (bool) finite) {
    return false;
  }

  return true;
}

#undef RLANG_MAX_DOUBLE_INT

bool r_is_character(r_obj* x, r_ssize n) {
  return r_typeof(x) == R_TYPE_character && has_correct_length(x, n);
}
bool r_is_raw(r_obj* x, r_ssize n) {
  return r_typeof(x) == R_TYPE_raw && has_correct_length(x, n);
}


// Coercion ----------------------------------------------------------

r_obj* rlang_vec_coercer(r_obj* dest) {
  switch(r_typeof(dest)) {
  case R_TYPE_logical: return rlang_ns_get("as_logical");
  case R_TYPE_integer: return rlang_ns_get("as_integer");
  case R_TYPE_double: return rlang_ns_get("as_double");
  case R_TYPE_complex: return rlang_ns_get("as_complex");
  case R_TYPE_character: return rlang_ns_get("as_character");
  case RAWSXP: return rlang_ns_get("as_bytes");
  default: r_abort("No coercion implemented for `%s`", Rf_type2str(r_typeof(dest)));
  }
}

void r_vec_poke_coerce_n(r_obj* x, r_ssize offset,
                         r_obj* y, r_ssize from, r_ssize n) {
  if (r_typeof(y) == r_typeof(x)) {
    r_vec_poke_n(x, offset, y, from, n);
    return ;
  }
  if (r_is_object(y)) {
    r_abort("Can't splice S3 objects");
  }

  // FIXME: This callbacks to rlang R coercers with an extra copy.
  r_obj* coercer = rlang_vec_coercer(x);
  r_obj* call = KEEP(Rf_lang2(coercer, y));
  r_obj* coerced = KEEP(r_eval(call, R_BaseEnv));

  r_vec_poke_n(x, offset, coerced, from, n);
  FREE(2);
}

void r_vec_poke_coerce_range(r_obj* x, r_ssize offset,
                             r_obj* y, r_ssize from, r_ssize to) {
  r_vec_poke_coerce_n(x, offset, y, from, to - from + 1);
}
