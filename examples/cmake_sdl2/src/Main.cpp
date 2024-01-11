#include <SDL.h>
#include <iostream>

int main()
{
    if (SDL_Init( SDL_INIT_VIDEO ) < 0) {
        std::cout << "SDL_Error: " << SDL_GetError() << std::endl;
    } else {

        SDL_CreateWindow("SDL2 Example",
            SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
            800, 600, SDL_WINDOW_SHOWN);

        SDL_Delay(2000);
    }

    return 0;
}
