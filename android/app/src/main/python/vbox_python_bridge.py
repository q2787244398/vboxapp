"""Wave G · RT-运1：Chaquopy 侧 Python 桥引导模块。

Android 无 `python3` 可执行文件，Dart `PythonBridgeEngine` 的
`Process.start('python3', ...)` 手段不成立，故改由 Chaquopy 在**进程内**运行蜘蛛脚本。
本模块把既有的 stdio ABI 语义原样复刻：用 Kotlin 传入的 io 对象替换
`sys.stdin` / `sys.stdout` / `sys.stderr`，使同一份蜘蛛脚本（如
`conformance/fixtures/python_echo_spider.py`）在子进程版与 Chaquopy 版之间**零改动复用**。

协议（对齐 contract/docs/abi_v1.md §7）：
  1. 脚本 `print('READY')` → 经 io.write 输出，宿主（Kotlin）据此确认就绪；
  2. 宿主逐行写入 JSON 请求 → `sys.stdin.readline()` 返回该行；
  3. 脚本逐行写回 JSON 响应 → 经 io.write 返回宿主。
"""


def run(script, io):
    """在替换后的 stdio 上执行蜘蛛脚本（阻塞至脚本退出）。

    :param script: 蜘蛛脚本源码（与子进程版同一份 .py 内容）
    :param io: Kotlin `PythonPlugin.StdioBridge`（`readLine()` / `write(s)`）
    """
    import sys

    class _Stdin:
        """`sys.stdin` 替身：readline() 阻塞取宿主请求行，EOF 时返回空串。"""

        def readline(self, *args, **kwargs):
            line = io.readLine()
            if line is None:
                return ''
            return line if line.endswith('\n') else line + '\n'

        def read(self, *args, **kwargs):
            return self.readline()

        def readable(self):
            return True

    class _Writer:
        """`sys.stdout` / `sys.stderr` 替身：write() 经 io 回传宿主。"""

        def write(self, text):
            if text:
                io.write(text)
            return len(text)

        def flush(self):
            pass

        def writable(self):
            return True

    sys.stdin = _Stdin()
    sys.stdout = _Writer()
    sys.stderr = _Writer()

    namespace = {'__name__': '__main__', '__file__': '<vbox_spider>'}
    exec(compile(script, '<vbox_spider>', 'exec'), namespace)
