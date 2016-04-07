#pragma once

/* Includes ***************************************************************************************/
#include <string>
#include <map>
#include "Comp.hpp"
#include "Prop.hpp"

/* Using ******************************************************************************************/
using std::string;
using std::map;
using std::ostream;
using std::pair;

/* Namespace **************************************************************************************/
namespace engine
{

/* Entity Declaration *****************************************************************************/

/*
** An entity in the game world.
*/
class Entity
{
public:
	// Constructor/Deconstructor
	Entity();
	~Entity();

	// Types
	typedef map<unsigned int, Prop *> PropMap;
	typedef PropMap::const_iterator PropIterator;
	typedef map<unsigned int, Comp *> CompMap;
	typedef CompMap::const_iterator CompIterator;

	// Functions
	Prop *FindProp(const string &name);
	void AddComp(Comp *comp);

	// Template Functions
	template<class T>
	ValueProp<T> *GetValueProp(const string &name, T initialValue = 0);
	template<class T>
	MessageProp<T> *GetMessageProp(const string &name);

private:
	// Functions
	Prop *&GetProp(const string &name);

	// Members
	PropMap props;
	CompMap comps;

	// Friends
	friend ostream & operator<<(ostream &os, const Entity& e);
};

// Operators
ostream & operator<<(ostream &os, const Entity &e);

/* Entity Template Definition *********************************************************************/

// Template Functions ------------------------------------------------------------------------------

/*
** Returns the ValueProp associated with the given name or creates it if no association exists.
*/
template<class T>
ValueProp<T> *Entity::GetValueProp(const string &name, T initialValue)
{
	// Get a reference to the property associated with this name
	ValueProp<T> *&prop = (ValueProp<T> *&) GetProp(name);

	// Create the property if no association was found
	if (!prop) {
		prop = new ValueProp<T>(name, this, initialValue);
	}

	return prop;
}

/*
** Returns the MessageProp associated with the given name or creates it if no association exists.
*/
template<class T>
MessageProp<T> *Entity::GetMessageProp(const string &name)
{
	// Get a reference to the property associated with this name
	MessageProp<T> *&prop = (MessageProp<T> *&) GetProp(name);

	// Create the property if no association was found
	if (!prop) {
		prop = new MessageProp<T>(name, this);
	}

	return prop;
}

} // namespace engine