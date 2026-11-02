// 工具侧进程原语回归（无头）：退出码、超时、后台起停与探活。

///|
/// 平台跳板：POSIX 用例依赖 /bin/*，Windows 上首跑即报 Err。
fn posix_only() -> Bool {
  match run_wait("/bin/true", [], 5000) {
    Ok(_) => true
    Err(_) => {
      println("[skip] 无 /bin/true（Windows），跳过 POSIX 用例")
      false
    }
  }
}

///|
test "run_wait：退出码与超时" {
  if posix_only() {
    assert_eq(run_wait("/bin/true", [], 5000), Ok(0))
    assert_eq(run_wait("/bin/false", [], 5000), Ok(1))
    assert_true(
      match run_wait("/bin/sleep", ["2"], 100) {
        Err(e) => contains_sub_p(e, "超时")
        Ok(_) => false
      },
    )
  }
}

///|
test "spawn / alive / kill：后台进程生命周期" {
  if posix_only() {
    match spawn("/bin/sleep", ["5"], "/tmp/mng_proc_test.log") {
      Ok(pid) => {
        assert_true(alive(pid))
        assert_true(kill(pid))
        let mut waited = 0
        while alive(pid) && waited < 2000 {
          sleep_ms(50)
          waited += 50
        }
        assert_true(!alive(pid))
      }
      Err(e) => abort("spawn: \{e}")
    }
  }
}

///|
test "run_wait：起不来的可执行报 Err" {
  assert_true(
    match run_wait("/nonexistent/mng_nope", [], 1000) {
      Ok(_) => false
      Err(e) => contains_sub_p(e, "起不来")
    },
  )
}

///|
fn contains_sub_p(s : String, sub : String) -> Bool {
  let a = s.to_array()
  let b = sub.to_array()
  let n = a.length()
  let m = b.length()
  if m == 0 || m > n {
    return m == 0
  }
  let mut i = 0
  while i + m <= n {
    let mut ok = true
    for k = 0; k < m; k = k + 1 {
      if a[i + k] != b[k] {
        ok = false
      }
    }
    if ok {
      return true
    }
    i = i + 1
  }
  false
}
