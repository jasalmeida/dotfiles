-- AMD iGPU + NVIDIA dGPU laptops: render and decode on the AMD GPU by default.
--
-- Omarchy's nvidia.lua sets __GLX_VENDOR_LIBRARY_NAME=nvidia and
-- LIBVA_DRIVER_NAME=nvidia whenever an NVIDIA GPU exists. That suits an
-- NVIDIA-only desktop, but on a hybrid laptop it sends OpenGL (including
-- XWayland apps) and video decode to the NVIDIA GPU and keeps it awake.
-- Override both so the NVIDIA GPU stays asleep unless an app asks for it.
--
-- Sysfs globs only: lspci would wake the sleeping GPU.
if o.shell_succeeds("ls /sys/bus/pci/drivers/amdgpu/0000:* /sys/bus/pci/drivers/nvidia/0000:*") then
  hl.env("__GLX_VENDOR_LIBRARY_NAME", "mesa")
  hl.env("LIBVA_DRIVER_NAME", "radeonsi")
end

-- To run one app on the NVIDIA GPU, launch it with:
--   __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only <app>
