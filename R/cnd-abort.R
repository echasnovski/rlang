#' Signal an error, warning, or message
#'
#' @description
#'
#' These functions are equivalent to base functions [base::stop()],
#' [base::warning()], and [base::message()], but make it easy to supply
#' condition metadata:
#'
#' * Supply `class` to create a classed condition. Typed
#'   conditions can be captured or handled selectively, allowing for
#'   finer-grained error handling.
#'
#' * Supply metadata with named `...` arguments. This data will be
#'   stored in the condition object and can be examined by handlers.
#'
#' `interrupt()` allows R code to simulate a user interrupt of the
#' kind that is signalled with `Ctrl-C`. It is currently not possible
#' to create custom interrupt condition objects.
#'
#'
#' @section Backtrace:
#'
#' Unlike `stop()` and `warning()`, these functions don't include call
#' information by default. This saves you from typing `call. = FALSE`
#' and produces cleaner error messages.
#'
#' A backtrace is always saved into error objects. You can print a
#' simplified backtrace of the last error by calling [last_error()]
#' and a full backtrace with `summary(last_error())`.
#'
#' You can also display a backtrace with the error message by setting
#' the option [`rlang_backtrace_on_error`]. It supports the following
#' values:
#'
#' * `"reminder"`: Invite users to call `rlang::last_error()` to see a
#'   backtrace.
#' * `"branch"`: Display a simplified backtrace.
#' * `"collapse"`: Display a collapsed backtrace tree.
#' * `"full"`: Display a full backtrace tree.
#' * `"none"`: Display nothing.
#'
#' @section Mufflable conditions:
#'
#' Signalling a condition with `inform()` or `warn()` causes a message
#' to be displayed in the console. These messages can be muffled with
#' [base::suppressMessages()] or [base::suppressWarnings()].
#'
#' On recent R versions (>= R 3.5.0), interrupts are typically
#' signalled with a `"resume"` restart. This is however not
#' guaranteed.
#'
#' @inheritParams cnd
#' @param message The message to display. Character vectors are
#'   formatted with [format_bullets()]. The first element
#'   defines a message header and the rest of the vector defines
#'   bullets. Bullets named `i` and `x` define info and error bullets
#'   respectively, with special Unicode and colour formatting applied
#'   if possible.
#'
#'   If a message is not supplied, it is expected that the message is
#'   generated lazily through [conditionMessage()][cnd_message]. In
#'   that case, `class` must be supplied. Only `inform()` allows empty
#'   messages as it is occasionally useful to build user output
#'   incrementally.
#' @param class Subclass of the condition. This allows your users
#'   to selectively handle the conditions signalled by your functions.
#' @param ... Additional data to be stored in the condition object.
#' @param .subclass This argument was renamed to `class` in rlang
#'   0.4.2.  It will be deprecated in the next major version. This is
#'   for consistency with our conventions for class constructors
#'   documented in <https://adv-r.hadley.nz/s3.html#s3-subclassing>.
#'
#' @seealso [with_abort()] to convert all errors to rlang errors.
#' @examples
#' # These examples are guarded to avoid throwing errors
#' if (FALSE) {
#'
#' # Signal an error with a message just like stop():
#' abort("Something bad happened")
#'
#' # Give a class to the error:
#' abort("Something bad happened", "somepkg_bad_error")
#'
#' # This will allow your users to handle the error selectively
#' tryCatch(
#'   somepkg_function(),
#'   somepkg_bad_error = function(err) {
#'     warn(conditionMessage(err)) # Demote the error to a warning
#'     NA                          # Return an alternative value
#'   }
#' )
#'
#' # You can also specify metadata that will be stored in the condition:
#' abort("Something bad happened", "somepkg_bad_error", data = 1:10)
#'
#' # This data can then be consulted by user handlers:
#' tryCatch(
#'   somepkg_function(),
#'   somepkg_bad_error = function(err) {
#'     # Compute an alternative return value with the data:
#'     recover_error(err$data)
#'   }
#' )
#'
#' # If you call low-level APIs it is good practice to handle
#' # technical errors and rethrow them with a more meaningful
#' # message. Always prefer doing this from `withCallinghandlers()`
#' # rather than `tryCatch()` because the former preserves the stack
#' # on error and makes it possible for users to use `recover()`.
#' file <- "http://foo.bar/baz"
#' try(withCallinghandlers(
#'   download(file),
#'   error = function(err) {
#'     msg <- sprintf("Can't download `%s`", file)
#'     abort(msg, parent = err)
#' }))
#' # Note how we supplied the parent error to `abort()` as `parent` to
#' # get a decomposition of error messages across error contexts.
#'
#' # Unhandled errors are saved automatically by `abort()` and can be
#' # retrieved with `last_error()`. The error prints with a simplified
#' # backtrace:
#' abort("Saved error?")
#' last_error()
#'
#' # Use `summary()` to print the full backtrace and the condition fields:
#' summary(last_error())
#'
#' }
#' @export
abort <- function(message = NULL,
                  class = NULL,
                  ...,
                  trace = NULL,
                  parent = NULL,
                  .subclass = deprecated()) {
  validate_signal_args(.subclass)

  if (is_null(trace) && is_null(peek_option("rlang:::disable_trace_capture"))) {
    # Prevents infloops when rlang throws during trace capture
    with_options("rlang:::disable_trace_capture" = TRUE, {
      trace <- trace_back()

      # Remove throwing context. Especially important when rethrowing
      # from a condition handler because in that case there are a
      # bunch of irrelevant frames in the trailing branch of the call
      # stack. We want to display the call tree branch that is
      # relevant to users in simplified backtraces.
      if (is_null(parent)) {
        context <- trace_length(trace)
      } else {
        context <- trace_capture_depth(trace)
      }

      trace <- trace_trim_context(trace, context)
    })
  }

  message <- validate_signal_message(message, class)
  message <- collapse_cnd_message(message)

  cnd <- error_cnd(class,
    ...,
    message = message,
    parent = parent,
    trace = trace
  )
  signal_abort(cnd)
}

signal_abort <- function(cnd) {
  if (is_true(peek_option("rlang:::force_unhandled_error"))) {
    # Fall back with the full rlang error
    fallback <- cnd
  } else {
    # Let exiting and calling handlers handle the fully typed
    # condition. The error message hasn't been altered yet and won't
    # affect handling functions like `try()`.
    signalCondition(cnd)

    # If we're still here, the error is unhandled. Fall back with a
    # bare condition to avoid calling handlers logging the same error
    # twice
    fallback <- cnd("rlang_error")
  }

  # Save the unhandled error for `rlang::last_error()`.
  last_error_env$cnd <- cnd

  if (is_interactive()) {
    # Generate the error message, possibly with a backtrace or reminder
    fallback$message <- paste_line(
      conditionMessage(cnd),
      format_onerror_backtrace(cnd)
    )
    fallback$rlang_entraced <- TRUE
  } else {
    file <- peek_option("rlang:::error_pipe") %||% stderr()
    msg <- conditionMessage(cnd)
    fallback$message <- msg

    cat("Error: ", msg, "\n", sep = "", file = file)

    # Print the backtrace eagerly in non-interactive sessions because
    # the length of error messages is limited (#856)
    cat(format_onerror_backtrace(cnd), "\n", sep = "", file = file)

    # Turn off the regular error printing to avoid printing the error
    # twice
    local_options(show.error.messages = FALSE)
  }

  stop(fallback)
}

trace_trim_context <- function(trace, idx) {
  if (!is_scalar_integerish(idx)) {
    abort("`frame` must be a frame environment or index")
  }

  to_trim <- seq2(idx, trace_length(trace))
  if (length(to_trim)) {
    trace <- trace_subset(trace, -to_trim)
  }

  trace
}

# Assumes we're called from a calling or exiting handler
trace_capture_depth <- function(trace) {
  calls <- trace$calls
  default <- length(calls)

  if (length(calls) <= 3L) {
    return(default)
  }

  # withCallingHandlers()
  wch_calls <- calls[seq2(length(calls) - 3L, length(calls) - 1L)]
  if (is_call(wch_calls[[1]], "signal_abort") &&
      is_call(wch_calls[[2]], "signalCondition") &&
      is_call(wch_calls[[3]]) && is_function(wch_calls[[3]][[1]])) {
    return(length(calls) - 4L)
  }

  exiting_call <- quote(value[[3L]](cond))
  exiting_n <- detect_index(calls, identical, exiting_call, .right = TRUE)

  # tryCatch()
  if (exiting_n != 0L) {
    try_catch_calls <- calls[seq_len(exiting_n - 1L)]
    try_catch_n <- detect_index(try_catch_calls, is_call, "tryCatch", .right = TRUE)
    if (try_catch_n != 0L) {
      return(try_catch_n)
    } else {
      return(default)
    }
  }

  default
}

#' Display backtrace on error
#'
#' @description
#'
#' Errors thrown with [abort()] automatically save a backtrace that
#' can be inspected by calling [last_error()]. Optionally, you can
#' also display the backtrace alongside the error message by setting
#' the option `rlang_backtrace_on_error` to one of the following
#' values:
#'
#' * `"reminder"`: Display a reminder that the backtrace can be
#'   inspected by calling [rlang::last_error()].
#' * `"branch"`: Display a simplified backtrace.
#' * `"collapse"`: Display a collapsed backtrace tree.
#' * `"full"`: Display the full backtrace tree.
#'
#'
#' @section Promote base errors to rlang errors:
#'
#' Call `options(error = rlang::entrace)` to instrument base
#' errors with rlang features. This handler does two things:
#'
#' * It saves the base error as an rlang object. This allows you to
#'   call [last_error()] to print the backtrace or inspect its data.
#'
#' * It prints the backtrace for the current error according to the
#'   `rlang_backtrace_on_error` option.
#'
#' @name rlang_backtrace_on_error
#' @aliases add_backtrace
#'
#' @examples
#' # Display a simplified backtrace on error for both base and rlang
#' # errors:
#'
#' # options(
#' #   rlang_backtrace_on_error = "branch",
#' #   error = rlang::entrace
#' # )
#' # stop("foo")
NULL

# Whenever the backtrace-on-error format is changed, the version in
# `inst/backtrace-ver` and in `tests/testthat/helper-rlang.R` must be
# bumped. This way `devtools::test()` will skip the tests that require
# the dev version to be installed locally.
format_onerror_backtrace <- function(cnd) {
  trace <- cnd$trace

  # Show backtrace of oldest parent
  while (is_condition(cnd$parent)) {
    cnd <- cnd$parent
    if (!is_null(cnd$trace)) {
      trace <- cnd$trace
    }
  }

  if (is_null(trace) || !trace_length(trace)) {
    return(NULL)
  }

  show_trace <- show_trace_p()

  opts <- c("none", "reminder", "branch", "collapse", "full")
  if (!is_string(show_trace) || !show_trace %in% opts) {
    options(rlang_backtrace_on_error = NULL)
    warn("Invalid `rlang_backtrace_on_error` option (resetting to `NULL`)")
    return(NULL)
  }

  if (show_trace == "none") {
    return(NULL)
  }
  if (show_trace == "reminder") {
    if (is_interactive()) {
      reminder <- silver("Run `rlang::last_error()` to see where the error occurred.")
    } else {
      reminder <- NULL
    }
    return(reminder)
  }

  if (show_trace == "branch") {
    max_frames <- 10L
  } else {
    max_frames <- NULL
  }

  simplify <- switch(show_trace,
    full = "none",
    reminder = "branch", # Check size of backtrace branch
    show_trace
  )

  paste_line(
    "Backtrace:",
    format(trace, simplify = simplify, max_frames = max_frames)
  )
}

show_trace_p <- function() {
  old_opt <- peek_option("rlang__backtrace_on_error")
  if (!is_null(old_opt)) {
    warn_deprecated(paste_line(
      "`rlang__backtrace_on_error` is no longer experimental.",
      "It has been renamed to `rlang_backtrace_on_error`. Please update your RProfile."
    ))
    return(old_opt)
  }

  opt <- peek_option("rlang_backtrace_on_error")
  if (!is_null(opt)) {
    return(opt)
  }

  # FIXME: parameterise `is_interactive()`?
  interactive <- with_options(
    knitr.in.progress = NULL,
    rstudio.notebook.executing = NULL,
    is_interactive()
  )

  if (interactive) {
    "reminder"
  } else {
    "full"
  }
}

#' Last `abort()` error
#'
#' @description
#'
#' * `last_error()` returns the last error thrown with [abort()]. The
#'   error is printed with a backtrace in simplified form.
#'
#' * `last_trace()` is a shortcut to return the backtrace stored in
#'   the last error. This backtrace is printed in full form.
#'
#' @export
last_error <- function() {
  if (is_null(last_error_env$cnd)) {
    abort("Can't show last error because no error was recorded yet")
  }

  cnd <- last_error_env$cnd
  cnd$rlang$internal$from_last_error <- TRUE
  cnd
}
#' @rdname last_error
#' @export
last_trace <- function() {
  err <- last_error()
  err$rlang$internal$print_simplify <- "none"
  err
}

# This is where we save errors for `last_error()`
last_error_env <- new.env(parent = emptyenv())
last_error_env$cnd <- NULL
