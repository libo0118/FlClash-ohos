import type { HvigorPlugin, HvigorNode } from '@ohos/hvigor';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import path from 'node:path';

const execFileAsync = promisify(execFile);

const buildkitDir = path.resolve(__dirname, '..');
const projectRoot = path.resolve(__dirname, '..', '..', '..', '..');

export function setupPlugin(): HvigorPlugin {
  return {
    pluginId: 'SetupPlugin',
    apply(node: HvigorNode) {
      node.registerTask({
        name: 'setup',
        run: async () => {
          const launcher = path.join(
            buildkitDir,
            'build_ohos.cjs',
          );

          const { stdout, stderr } = await execFileAsync(
            process.execPath,
            [launcher],
            {
              cwd: projectRoot,
              env: {
                ...process.env,
                APP_ENV: process.env.APP_ENV ?? 'pre',
              },
            },
          );
          if (stdout) console.log(stdout);
          if (stderr) console.error(stderr);
        },
        postDependencies: ['default@ConfigureCmake'],
      });
    },
  };
}
