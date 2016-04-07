/* Includes ***************************************************************************************/
#include "Comp.hpp"

#include <iostream>

/* Using ******************************************************************************************/
using std::ostream;
using std::pair;

/* Namespace **************************************************************************************/
namespace engine
{

/* Comp Definition ********************************************************************************/

// Static Members --------------------------------------------------------------

Comp::CompListMap Comp::instanceListMap;

// Constructor/Deconstructor ---------------------------------------------------

Comp::Comp(const string &name) : Named<Comp>(name)
	, owner(NULL)
{
}

Comp::~Comp()
{
	// Detach this Comp from our owner Entity
	Detach();

	// Debug
	std::cout << "Freeing Comp " << GetName() << std::endl;
}

// Static Functions ------------------------------------------------------------

void Comp::UpdateAllComps(sf::RenderWindow &app)
{
	CompListMap::iterator iMap = instanceListMap.begin(), eMap = instanceListMap.end();

	// Iterate over map of Comp lists
	for (; iMap != eMap; iMap++) {
		// Iterate over Comp list
		CompList instanceList = iMap->second;

		CompList::iterator iList = instanceList.begin(), eList = instanceList.end();

		if (iList != eList) {
			// Update the Comp class
			(*iList)->UpdateComp(app);

			// Update the instances of the Comp
			for (; iList != eList; iList++) {
				(*iList)->Update(app);
			}
		}
	}
}

// Functions -------------------------------------------------------------------

/*
** Attaches this Comp.
*/
void Comp::Attach(Entity *e)
{
	// Set owner
	owner = e;

	// Add this instance to the update list
	CompList &instanceList = instanceListMap[GetId()];

	instanceList.push_front(this);
	instanceListIndex = instanceList.begin();

	// Initialize this instance
	Initialize();
}

/*
** Detaches this Comp.
*/
void Comp::Detach()
{
	// Confirm we are attached to an Entity
	if (owner) {
		// Remove ourselves from the Comp list
		instanceListMap[GetId()].erase(instanceListIndex);

		// Remove ourselves from our owner Entity
		owner = NULL;
	}
}

/*
** Prints this Comp to the given stream.
*/
void Comp::PrintTo(ostream &os) const
{
	os << GetName();
}

// Operators -------------------------------------------------------------------
ostream & operator<<(ostream &os, const Comp &c)
{
	c.PrintTo(os);
	return os;
}

} // namespace engine