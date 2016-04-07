#pragma once

/* Includes ***************************************************************************************/
#include "Named.hpp"

#include <SFML/Graphics.hpp>

#include <string>
#include <map>
#include <list>
#include <ostream>

/* Using ******************************************************************************************/
using std::string;
using std::map;
using std::list;
using std::ostream;
using std::pair;

/* Namespace **************************************************************************************/
namespace engine
{

/* Forward Declarations ***************************************************************************/
class Entity;
	
/* Comp Declaration *******************************************************************************/
class Comp : public Named<Comp>
{
public:
	// Constructor/Deconstructor
	Comp(const string &name);
	virtual ~Comp();

	// Types
	typedef list<Comp *> CompList;
	typedef map<unsigned int, CompList> CompListMap;

	// Static Functions
	static void UpdateAllComps(sf::RenderWindow &app);

	// Functions
	virtual void PrintTo(ostream &os) const;
	void Attach(Entity *e);
	void Detach();

	virtual void UpdateComp(sf::RenderWindow &app) {};
	virtual void Initialize() {};
	virtual void Update(sf::RenderWindow &app) {};

protected:
	// Members
	Entity *owner;

private:
	// Static Members
	static CompListMap instanceListMap;

	// Members
	CompList::iterator instanceListIndex;

	// Functions
	void AddToUpdateList();
	void RemoveFromUpdateList();
};

// Operators
ostream & operator<<(ostream &os, const Comp &c);

} // namespace engine