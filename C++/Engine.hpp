#pragma once

/* Includes ***************************************************************************************/
#include <string>

/* Using ******************************************************************************************/
using std::string;

/* Namespace **************************************************************************************/
namespace engine
{

/* Engine Definition ******************************************************************************/
class Engine
{
public:
	// Deconstructor
	~Engine() { };

	// Static Functions
	static Engine &GetEngine() { static Engine e; return e; }

	void Run();
	void SetTitle(string title) { this->title = title; }

private:
	// Members
	string title;

	// Constructor
	Engine() { };
};

} // namespace engine