# Custom caelestia colour schemes (fork only)

Register a scheme by linking it into the caelestia CLI's scheme folder, then select it:

    sudo ln -sfn ~/.local/share/caelestia/themes/cyberpunk /usr/lib/python3.*/site-packages/caelestia/data/schemes/cyberpunk
    caelestia scheme set -n cyberpunk -f neon -m dark

Re-run the `ln` after a Python version bump (the site-packages path changes).
