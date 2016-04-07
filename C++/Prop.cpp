/* Includes ***************************************************************************************/
#include "Prop.hpp"

#include <iostream>

/* Namespace **************************************************************************************/
namespace engine
{

/* Prop Definition ********************************************************************************/

// Constructor/Deconstructor ---------------------------------------------------
Prop::Prop(const string &name, Entity *owner) : Named<Prop>(name)
	, owner(owner)
{
}

Prop::~Prop()
{
	std::cout << "Freeing Prop " << GetName() << std::endl;
}

// Operators -------------------------------------------------------------------
ostream & operator<<(ostream &os, const Prop &prop)
{
	prop.PrintTo(os);
	return os;
}

}