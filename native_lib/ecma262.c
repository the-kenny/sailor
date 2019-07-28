#include <erl_nif.h>

extern char *g_fmt(char *, double);

ERL_NIF_TERM g_fmt_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
  double d = 0.0;
  if (!enif_get_double(env, argv[0], &d)) {
    return enif_make_badarg(env);
  }

  char buf[32];
  g_fmt((char*)&buf, d);

  return enif_make_string(env, buf, 32);
}

static ErlNifFunc nif_funcs[] = {
  {"g_fmt", 1, g_fmt_nif},
};

ERL_NIF_INIT(Elixir.Sailor.Ecma262, nif_funcs, NULL, NULL, NULL, NULL)