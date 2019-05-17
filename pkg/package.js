// This is run on Travis, and presumably eventually AppVeyor, builds. It's supposed to be as
// cross-platform as possible, unlike the adjacent release-script, which I only care if *I* can run.
const current_ppx_id = require("ppx-deriving/identify"),
   path = require("path"),
   fs = require("fs"),
   cpy = require("cpy"),
   makeDir = require("make-dir"),
   archiver = require("archiver")

const zipfile = `ppx-deriving-${current_ppx_id}.zip`,
   dist_dir = "dist/",
   submodule_ppx_dir = `ppx-deriving/ppx-deriving-${current_ppx_id}/`,
   build_dir = "_build/default/.ppx",
   zip_dir = "ppx/",
   exe = "ppx.exe"

// FIXME: Does any of these even work on Windows
;(async () => {
   // Most Dune tasks in this project build *several* ppx drivers (per-target, basically.) We can't
   // differentiate between these, though; so it's important that `dune clean` is run before the
   // target that builds our actual `.std`-ppx binary. I half-ass determining this by ensuring
   // there's only one file in Dune's `.ppx` directory.
   const ppxes = await fs.promises.readdir(build_dir)
   if (ppxes.length !== 1) {
      console.error(`Expected a single ppx-binary in ${build_dir}; found multiple items`)
      throw new Error("Too many directory entries")
   }
   const ppx_id = ppxes[0]

   // Copy the executable to the submodule,
   console.log(`Copy: ${path.join(build_dir, ppx_id, exe)} -> ${submodule_ppx_dir}`)
   await cpy(path.join(build_dir, ppx_id, exe), submodule_ppx_dir)

   // ... and again to the zip-directory,
   console.log(`Copy: ${path.join(build_dir, ppx_id, exe)} -> ${zip_dir}`)
   await cpy(path.join(build_dir, ppx_id, exe), zip_dir)

   // Create a zip-archive,
   const dist = await makeDir(dist_dir)
   console.log(`Zip: ${path.join(zip_dir, exe)} >>> ${path.join(dist, zipfile)}`)
   const output = fs.createWriteStream(path.join(dist, zipfile)),
      archive = archiver("zip", { zlib: { level: 9 } })

   output.on("close", function() {
      console.log(`>> Zipped: ${archive.pointer()} total bytes`)
   })

   archive.pipe(output)
   archive.directory(zip_dir, false)
   archive.finalize()
})()
