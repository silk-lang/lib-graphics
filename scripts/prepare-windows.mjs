// Run from an x64 Visual Studio developer shell, after Silk has fetched lib-native.
import { resolve } from 'node:path';
import { run } from './internal.mjs';
import { nativeRoot } from './native-root.mjs';

if (process.platform !== 'win32') throw new Error('Windows preparation requires Windows');
run('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
  resolve(nativeRoot(), 'scripts/prepare-windows.ps1'),
  ...(process.env.SILK_CLANG ? ['-Clang', process.env.SILK_CLANG] : []),
  ...process.argv.slice(2)]);
