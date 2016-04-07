/* Includes ***************************************************************************************/
#include "Engine.hpp"

#include "Comp.hpp"

#include <SFML/Graphics.hpp>
#include <SFML/Audio.hpp> 

/* Using ******************************************************************************************/

/* Namespace **************************************************************************************/
namespace engine
{

// Functions -------------------------------------------------------------------
void Engine::Run()
{
	// Create the window of the application
	sf::RenderWindow app(sf::VideoMode(800, 600, 32), title);
	app.EnableVerticalSync(true);

	// Run forever
	while (app.IsOpened()) {
		// Handle events
		sf::Event e;
		while (app.PollEvent(e)) {
			// Close application
			if (e.Type == sf::Event::Closed) {
				app.Close();
				break;
			}
		}

		// Handle Comps
		Comp::UpdateAllComps(app);

		// Clear the window
		app.Clear();

		// Display things on screen
		app.Display();
	}
}

} // namespace engine