#pragma once

/* Includes ***************************************************************************************/
#include <string>
#include <map>
#include <ostream>
#include "Named.hpp"

/* Using ******************************************************************************************/
using std::string;
using std::map;
using std::ostream;
using std::pair;

/* Namespace **************************************************************************************/
namespace engine
{

/* Forward Declarations ***************************************************************************/
class Entity;

/* Prop Declaration *******************************************************************************/
class Prop : public Named<Prop>
{
public:
	// Constructor/Deconstructor
	Prop(const string &name, Entity *owner);
	virtual ~Prop();

	// Functions
	virtual void PrintTo(ostream &os) const = 0;

protected:
	// Members
	Entity *owner;

private:
	// Friends
	friend class Entity;
};

// Operators
ostream & operator<<(ostream &os, const Prop &p);

/* ValueProp Declaration **************************************************************************/
template<class T>
class ValueProp : public Prop
{
public:
	// Constructor/Deconstructor
	ValueProp(const string &name, Entity *owner, T value);
	virtual ~ValueProp();

	// Functions
	void PrintTo(ostream &os) const;
	T *GetValuePointer() const;

private:
	// Members
	T value;

	// Friends
	template<class T>
	friend ostream & operator<<(ostream &os, const ValueProp<T> &p);
};

/* MessageProp Declaration ************************************************************************/
template<class T>
class MessageProp : public Prop
{
public:
	// Constructor/Deconstructor
	MessageProp(const string &name, Entity *owner);
	virtual ~MessageProp();

	// Functions
	void PrintTo(ostream &os) const;
	void Send(T *value) const;

private:
	// Friends
	template<class T>
	friend ostream & operator<<(ostream &os, const MessageProp<T> &p);
};

/* ValueProp Template Definition ******************************************************************/

// Constructor/Deconstructor ---------------------------------------------------

/*
** Constructs this ValueProp.
*/
template<class T>
ValueProp<T>::ValueProp(const string &name, Entity *owner, T value)
	: Prop(name, owner)
	, value(value)
{

}

/*
** Deconstructs this ValueProp.
*/
template<class T>
ValueProp<T>::~ValueProp()
{

}

// Functions -------------------------------------------------------------------

/*
** Prints this ValueProp to the given stream.
*/
template<class T>
void ValueProp<T>::PrintTo(ostream &os) const
{
	os << "(Value)   " << GetName() << "\t= " << value;
}

/*
** Gets a pointer to the value that this ValueProp holds.
*/
template<class T>
T *ValueProp<T>::GetValuePointer() const
{
	return (T *) &value;
}

// Operators -------------------------------------------------------------------

/*
** << operator.
*/
template<class T>
ostream & operator<<(ostream &os, const ValueProp<T> &prop)
{
	prop.PrintTo(os);
	return os;
}

/* MessageProp Template Definition ****************************************************************/

// Constructor/Deconstructor ---------------------------------------------------

/*
** Constructs this MessageProp.
*/
template<class T>
MessageProp<T>::MessageProp(const string &name, Entity *owner)
	: Prop(name, owner)
{

}

/*
** Deconstructs this MessageProp.
*/
template<class T>
MessageProp<T>::~MessageProp()
{

}

// Functions -------------------------------------------------------------------

/*
** Prints this MessageProp to the given stream.
*/
template<class T>
void MessageProp<T>::PrintTo(ostream &os) const
{
	os << "(Message) " << GetName();
}

/*
** Sends a message with the given value.
*/
template<class T>
void MessageProp<T>::Send(T *value) const
{
	// Do nothing
}

// Operators -------------------------------------------------------------------

/*
** << operator.
*/
template<class T>
ostream & operator<<(ostream &os, const MessageProp<T> &prop)
{
	prop.PrintTo(os);
	return os;
}

} // namespace engine